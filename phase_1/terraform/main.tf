terraform {
  # Terraform本体とProviderのバージョン固定（チームで再現性を担保）
  required_version = "~> 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# =========================
# Provider（GCPと話す通訳係）
# =========================
provider "google" {
  project = var.project_id  # どのGCPプロジェクトで作業するか
  region  = var.region      # リージョン既定（リソース側で上書きする場合もある）
}

# =========================================
# API 有効化（正しいリソース名に注意！）
# - GCPの各サービスは「APIをON」にしないと使えない
# - Terraformでは google_project_service を使う
# - Service Usage API を先にONにして他サービスを操作可能にする
# =========================================
resource "google_project_service" "service_usage" {
  project = var.project_id
  service = "serviceusage.googleapis.com"
  disable_on_destroy = false

  # このAPI自体をONにしないと、storage等のAPIの有効化操作が403で失敗する。
}

# =========================================
# Cloud Storage API（Service Usage APIに依存）
# =========================================
resource "google_project_service" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"
  disable_on_destroy = false

  # Service Usage APIの有効化を待ってから実行させる
  depends_on = [google_project_service.service_usage]

  # 参考：
  # 既にコンソールで手動有効化済みでも、IaCで明示しておくと
  # 新規プロジェクトのブートストラップでも自動でONにでき、
  # 「初回applyでAPI未有効エラー」を避けられます。
  #
  # また、誰かが誤ってOFFにした場合でも、次のapplyでONに戻せる＝再現性が上がる。
}

# =========================================
# Cloud Storage バケット本体
# - これは Storage API が有効でないと作れない
# - 初回applyの順序レースを防ぐため depends_on を付けて明示的に依存
# =========================================
resource "google_storage_bucket" "app_bucket" {
  name                        = "${var.project_id}-phase1-bucket"  # GCS名はグローバル一意
  location                    = var.region
  uniform_bucket_level_access = true

  # ★ポイント：
  # このリソース自体は google_project_service.storage を参照していないため
  # Terraformは依存関係を自動推論できません。
  # そのため、初回applyで「APIがまだONになっていない → 失敗」のレースが起き得ます。
  # depends_on で順序を固定し、確実にAPI→バケットの順で作らせます。
  depends_on = [google_project_service.storage]
}

# =========================================
# Output（完成後の“引き渡しメモ”）
# - 必須ではないが、以下の用途で強力：
#   1) 手動確認：`terraform output bucket_name` で素早く把握
#   2) 他モジュールへ渡す：moduleの公開インターフェースとして再利用
#   3) CI/CDでの参照：デプロイURL/IDなどを後続ジョブに渡す
# - 機密は出力しない/するなら sensitive=true を付与
# =========================================
output "bucket_name" {
  value = google_storage_bucket.app_bucket.name
  # sensitive = false  # ※機密なら true にする
}
