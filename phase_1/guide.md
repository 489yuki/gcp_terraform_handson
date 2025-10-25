了解！Phase 1 を“今日から Terraform 始めた人向け”に、やさしく一気に掴めるようにまとめます。小さな実例と例えを交えていきます。

---

# 1. Terraform の基本概念（超ざっくり像 → 少しだけ詳しく）

## Terraform は何者？

- クラウドの設定書（設計図）＝**HCL**という言語で書く
- 設計図どおりに**作る・変える・壊す**を自動実行
- 何を持っているかの台帳＝**状態（state）** を管理

## 6 つの基本ピース

### 1) provider（プロバイダ）

> 「どのクラウドと話すか」を教える通訳さん
> GCP と話したい → `google` プロバイダを使う。

```hcl
terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}
provider "google" {
  project = var.project_id
  region  = var.region
}
```

### 2) resource（リソース）

> 「何を作るか」の実体。GCS バケツ、VPC、Cloud Run など。

```hcl
resource "google_storage_bucket" "app_bucket" {
  name     = "${var.project_id}-app-bucket"
  location = var.region
  uniform_bucket_level_access = true
}
```

### 3) variables（変数）

> 同じ設計図を**環境別に使い回すための差し込み口**。

```hcl
variable "project_id" { type = string }
variable "region"     { type = string  }
```

`terraform.tfvars` や `-var-file` で値を渡す。

### 4) outputs（出力）

> つくったものの**重要な情報を外に見せる**。あとで別モジュールへ渡すのにも使う。

```hcl
output "bucket_name" { value = google_storage_bucket.app_bucket.name }
```

### 5) locals（ローカル）

> 変数とロジックの中間。**計算や共通命名**をここで定義。

```hcl
locals {
  base_name = "${var.project_id}-${var.env}"
}
```

### 6) modules（モジュール）

> 設計図の**部品化**。
> VPC／Cloud Run／Cloud SQL など“意図の単位”でフォルダ化し、**同じものを dev/prod で再利用**。

```
modules/
  vpc/
    main.tf
    variables.tf
    outputs.tf
```

> 例え：レゴの「車パーツ」「家パーツ」。完成品（環境）は同じパーツの組み合わせと色違い。

---

# 2. コマンドの意味（実務でどう使うか）

- `terraform init`
  初期化。プラグイン（provider）をダウンロードし、作業フォルダを Terraform 化。
  **初回・provider 更新時・backend 変更時に必須。**

- `terraform plan`
  予定表の作成。「今の状態」→「HCL に書いた理想」まで**何を変更するか**を一覧化。
  **安全確認の心臓部。毎回見る。**

- `terraform apply`
  予定表どおり**実行**してクラウドを変更。`plan` を確認してから実行。
  CI では `apply` を保護（承認者のみ）にするのが基本。

- `terraform destroy`
  管理下のリソースを**全部削除**。検証用環境を片付ける時に便利。
  ※本番では通常使わない。

> 例え：
>
> - `init`＝工具と材料を揃える
> - `plan`＝見積書
> - `apply`＝工事
> - `destroy`＝原状回復

---

# 3. GCP の基本粒度（Project / Region / Zone / IAM / API）

- **Project**：**請求と権限の最小単位**。1 プロジェクト＝ 1 つの財布・権限境界。
  dev・prod を**プロジェクト分離**すると安全（請求も分かれやすく、事故が波及しない）。

- **Region**：地理的な大きい範囲（例：`asia-northeast1`＝東京）。
  **レイテンシ・料金・可用性**に影響。基本は同一リージョンに寄せる。

- **Zone**：Region の中の小部屋（`asia-northeast1-a/b/c`）。
  VM 系で必要。Cloud Run などは Region 指定のみで OK。

- **IAM（役割）**：誰が何をできるか（例：`roles/viewer`、`roles/storage.admin`）。
  **最小権限**を守る。人には編集権を極力付けず、**CI 用 SA**に必要最小だけ付与。

- **API 有効化（サービス有効化）**：
  各サービスはまず**API を ON**にしないと使えない（Storage、Run、SQL など）。
  Terraform で `google_project_service` を使って ON にできる。

---

# 4. 今日から動かせる最小プロジェクト（ハンズオン）

```
my-terraform/
  main.tf
  variables.tf
  outputs.tf
  terraform.tfvars    # あなたのGCP情報を書く
```

### `main.tf`

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# まずはAPIを有効化（Storageを例に）
resource "google_project_service" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"
}

# バケットを作る（最小）
resource "google_storage_bucket" "app_bucket" {
  name                        = "${var.project_id}-phase1-bucket"
  location                    = var.region
  uniform_bucket_level_access = true

  depends_on = [google_project_service.storage]
}

output "bucket_name" {
  value = google_storage_bucket.app_bucket.name
}
```

### `variables.tf`

```hcl
variable "project_id" { type = string }
variable "region"     { type = string }
```

### `terraform.tfvars`（自分の値に置き換え）

```hcl
project_id = "your-gcp-project-id"
region     = "asia-northeast1"
```

### 実行手順

```bash
# 初回だけ
gcloud auth application-default login   # ローカル認証（GUIが開きます）
cd my-terraform
terraform init
terraform plan      # 変更予定を確認
terraform apply     # y で実行
# ⇒ outputs に bucket_name が出たらOK

# 片付け（必要なら）
terraform destroy
```

> ※ 認証が通らないときは `gcloud config set project your-gcp-project-id` でプロジェクト指定も。

---

# 5. つまずきやすいポイント（先回りで回避）

- **認証エラー**
  `gcloud auth application-default login` を忘れがち。プロジェクトも `gcloud config set project ...` を確認。

- **API 未有効**
  「権限はあるのに作れない」「見つからない」→ `google_project_service` で該当 API を有効化。

- **命名衝突**
  GCS バケツ名は**グローバル一意**。`<project>-<用途>` 形式にして重複回避。

- **region/zone ミスマッチ**
  サービスがサポートするリージョン・ゾーンを確認。最初は **全部 `asia-northeast1`** で揃えるのが簡単。

---

# 6. モジュールの“入口”だけ覗く（Phase 2 の下準備）

同じ設計を dev / prod に使い回したい → **モジュール化**が武器。
まずはフォルダだけ切って、「同じ部品を呼び出す」イメージを持っておくと次が楽。

```
repo/
  modules/
    bucket/
      main.tf        # バケットのresourceをここに寄せる
      variables.tf
      outputs.tf
  environments/
    dev/
      main.tf        # modules/bucket を呼ぶだけ
      dev.tfvars
    prod/
      main.tf
      prod.tfvars
```

> 次フェーズでは、この形に“VPC モジュール”を入れて dev/prod を差分（tfvars）だけにします。

---

# 7. ゴール確認（Phase 1 合格の目安）

- [ ] `provider / resource / variable / output / local / module` の役割が説明できる
- [ ] `init → plan → apply → destroy` の流れで **GCS バケツ**を作って壊せた
- [ ] Project / Region / Zone / IAM / API 有効化 の違いが言える
- [ ] `terraform.tfvars` に値を分離できた（設計と値の分離）

---

# 8. もし難しく感じたところの“例え集”

- **Project**＝会社の**部門の財布**（請求と権限の境界）
- **Region/Zone**＝**都道府県/市区**（地域の粒度）
- **IAM**＝**入館証の権限**（入れる部屋と操作できる範囲）
- **provider**＝**通訳**（GCP と話すための翻訳係）
- **resource**＝**具体的な設備**（倉庫＝ GCS、道路＝ VPC）
- **variables**＝**図面の空欄**（現場ごとに数字や色を差し替え）
- **outputs**＝**完成後の引き渡しメモ**（住所・ID・URL の控え）
- **locals**＝**共通計算式**（命名規則や計算を一か所に）
- **modules**＝**レゴの部品箱**（家や車の“パーツ”を何度でも使う）

---

必要なら、上の最小プロジェクトを**そのままコピペで動く雛形**にしてお渡しします。
次は Phase 2（モジュール化と dev/prod 分離）へ進みましょう。
