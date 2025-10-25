# Phase 3 学習ガイド（状態管理と CI/CD の土台づくり）

Phase 2 でモジュール化と環境分離を学び、`dev` / `prod` が同じ構成になる土台ができました。Phase 3 のゴールは、この構成を **チームで安全に運用できるようにすること** です。具体的には次の 3 つを習得します。

- **リモートステート（GCS backend）**：Terraform の状態ファイルをチームで共有・保護する
- **IAM とサービスアカウント**：鍵を配らず、最小権限で運用するための基礎設定
- **CI/CD（GitHub Actions + OIDC）**：Pull Request で `plan` を可視化し、本番反映は承認つき `apply` に限定する

以下では、初心者でも進めやすいように「概念 → 手順 → 落とし穴」の順に解説し、例え話も交えて理解を深めます。

---

## 1. リモートステートとは？（なぜローカルに置いてはいけないのか）

### 1.1 ステートファイルの役割

- Terraform は「状態ファイル（`terraform.tfstate`）」に、**クラウド上のリソースと Terraform 設計図の対応表**を保存します。
- これがズレると、実際には存在するリソースを Terraform が「知らない」状態になり、誤って削除したり、重複作成したりする原因になります。

### 1.2 ローカル保管の危険性

- Phase 1・2 まではローカル PC に `terraform.tfstate` を置いていましたが、チーム運用では以下の問題が発生します。
  - 他のメンバーが最新の状態を持たず差分が食い違う
  - PC が故障/紛失すると復旧が困難
  - CI/CD（クラウド上のジョブ）からはローカルファイルにアクセスできない

### 1.3 リモートステート（GCS backend）の採用

- Google Cloud Storage（GCS）にバケットを作り、そこに state ファイルを置くことで、**常に最新状態を共有しながら Terraform を実行**できます。
- Terraform の `backend` 設定を使い、`terraform init` の段階で GCS を参照するようにします。

> 例え：`terraform.tfstate` は「工事現場の台帳」。ローカル PC にしまい込むのは個人ノート、GCS に置くと共有ホワイトボードになります。

---

## 2. GCS backend の構築ステップ

### 2.1 GCS バケットを用意する

- `infra-tfstate-<project-id>` のようにわかりやすい命名で、専用バケットを作成します。
- **ポイント**
  - `uniform_bucket_level_access = true` を設定して IAM をシンプルに
  - `versioning` を有効化すると、誤操作時に過去の state を復元しやすい
  - `prevent_destroy` を使うと誤削除を防止できる（terraform で管理するときに設定）

```
resource "google_storage_bucket" "tfstate" {
  name                        = "tfstate-${var.project_id}"
  location                    = "asia-northeast1"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

### 2.2 バケット用の IAM

- Terraform を実行するサービスアカウント（後述）が `roles/storage.objectAdmin`（または最小権限の組み合わせ）を持つ必要があります。
- 認証主体を個人メールではなくサービスアカウントに統一し、CI/CD からも同じ権限を使えるようにします。

### 2.3 `backend.tf` の設定

- `environments/dev/backend.tf` と `environments/prod/backend.tf` に、次のように GCS backend を宣言します。

```terraform
terraform {
  backend "gcs" {
    bucket = "tfstate-myproj-dev"   # 環境ごとにバケット or prefix を分離
    prefix = "terraform/state"      # state ファイルのパス（フォルダ相当）
  }
}
```

- **バケットを環境ごとに分けるか、同じバケットを prefix で分けるか** はチームの運用ポリシーに合わせます。一般的には、セキュリティを高めるならバケット自体を分ける、管理を簡単にするならバケットは共通で `prefix` を `dev/` `prod/` などに分ける、という選択になります。

### 2.4 `terraform init` で backend を有効化

- `backend.tf` を置いたフォルダで `terraform init` を実行すると、Terraform が GCS に接続し、`terraform.tfstate` をアップロードします。
- 既存のローカル state を移行する場合は、Terraform から「既存の state をリモートにコピーするか？」と聞かれるので `yes` を選択します。

> 注意：backend 設定を変更したら、`terraform init -migrate-state` を実行して state の移行を丁寧に行いましょう。

---

## 3. サービスアカウントと IAM 設計（鍵レス運用への第一歩）

### 3.1 サービスアカウント（SA）を用意する

- Terraform の実行専用のサービスアカウントを作り、人のアカウントと分離します。
- 例：`terraform-runner@<project-id>.iam.gserviceaccount.com`

### 3.2 必要な権限

- **基本方針**：最小権限を付与し、リソースを作りすぎない。Phase 3 の対象は VPC・サブネットなどネットワーク系と GCS backend なので、以下のロールを検討します。
  - `roles/editor` は NG（権限が広すぎる）
  - 代わりに `roles/compute.networkAdmin`, `roles/compute.securityAdmin`, `roles/storage.objectAdmin` など必要なものだけを付与
  - state 管理用バケットには `roles/storage.objectAdmin` またはカスタムロール

### 3.3 鍵レス運用につなげる（OIDC）

- 従来はサービスアカウントキー（JSON）をローカルや CI に配布していましたが、鍵ファイルは流出リスクが高いです。
- Phase 3 では GitHub Actions の **OIDC（OpenID Connect）** を利用し、鍵ファイルなしでサービスアカウントを信頼させます。
- SA 側では `roles/iam.workloadIdentityUser` を割り当て、GitHub のリポジトリ ID（`subject`）を条件にした IAM バインディングを作成します。

```
resource "google_service_account" "gha_runner" {
  account_id   = "terraform-runner"
  display_name = "Terraform Runner"
}

resource "google_service_account_iam_binding" "gha_oidc" {
  service_account_id = google_service_account.gha_runner.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/github-actions/attribute.repository/${var.github_repo}"
  ]
}
```

> 例え：サービスアカウントキー（JSON）は「玄関の合鍵」を配るイメージ。OIDC は「顔認証ゲート」を設置するイメージ。鍵を持ち歩かなくてよくなります。

---

## 4. GitHub Actions で CI/CD を構築する

### 4.1 ワークフローの全体像

- **Pull Request**：`terraform fmt` / `validate` / `tflint` / `tfsec` / `plan` を実行し、結果を PR にコメント
- **main ブランチへマージ**：保護ブランチに設定し、承認後に `terraform apply` を実行
- **権限**：CI で使う SA は最小権限、`apply` は人の承認が必須

### 4.2 GitHub Actions 用設定ファイル（例）

`.github/workflows/terraform.yaml`

```yaml
name: Terraform CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_TERRAFORM_SERVICE_ACCOUNT }}

      - name: Terraform Init
        run: terraform -chdir=phase_2/terraform/environments/dev init

      - name: Terraform Plan
        run: terraform -chdir=phase_2/terraform/environments/dev plan -var-file=dev.tfvars

  apply:
    needs: plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v2
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_TERRAFORM_SERVICE_ACCOUNT }}
      - run: terraform -chdir=phase_2/terraform/environments/prod init
      - run: terraform -chdir=phase_2/terraform/environments/prod apply -var-file=prod.tfvars -auto-approve
```

- `-chdir` オプションで対象フォルダを指定し、dev/prod を切り替えています。
- `GCP_WORKLOAD_IDENTITY_PROVIDER` や `GCP_TERRAFORM_SERVICE_ACCOUNT` は GitHub Secrets に設定します。
- `plan` ジョブでは `terraform show` の結果を PR コメントに投稿するステップを追加することも多いです（`github-commenter` 等のアクションが活用できます）。

### 4.3 CI/CD を本番で使うときの注意

- `apply` は保護ブランチ（`main`）に限定し、レビューと承認が終わったらマージ → 自動適用という流れを確立します。
- 緊急時のために手動 `apply` の手順も残しておきますが、原則は CI からのみ実行する方針を守ります。

---

## 5. 実践ステップ（段階的に導入するロードマップ）

### ステップ 1：GCS backend を導入

- `modules/storage_tfstate` のようなモジュールを作り、state 管理用バケットを Terraform で作成。
- `environments/dev/backend.tf` / `environments/prod/backend.tf` に backend 設定を記載。
- `terraform init -migrate-state` を実行して state を GCS へ移行。

### ステップ 2：サービスアカウントと IAM を整備

- Terraform 実行用 SA を作成し、必要最小限のロールを付与。
- Workload Identity Federation（OIDC）用の Workload Identity Pool と Provider を作成し、GitHub Actions から impersonate できるように設定。

### ステップ 3：GitHub Actions の CI を構築

- `plan` ジョブで fmt/validate/tflint/tfsec を実行し、結果が通らないと PR をマージできないようにブランチ保護ルールを設定。
- `plan` の結果を PR コメントに貼り付け、レビュー時に差分を確認できるようにする。
- `main` への push のみ `apply` を実行し、自動で prod に反映。

---

## 6. よくあるハマりポイントと対処法

- **GCS backend の権限不足**：CI から `terraform init` が失敗したら、サービスアカウントに `roles/storage.objectAdmin` もしくは `roles/storage.admin` が付いているか確認。
- **state のロック**：同時に複数の `terraform apply` を走らせるとロックが競合する。CI の実行は直列にする、または `terraform force-unlock` を慎重に使う。
- **OIDC 設定の subject ミスマッチ**：`principalSet://...` の `attribute.repository` が `owner/repo` 形式になっているか、ブランチ名条件を付ける場合は `attribute.ref` を利用する。
- **GitHub Secrets の不足**：OIDC の provider ID や SA メールアドレスを Secrets に登録し忘れると認証が失敗。
- **`apply` の自動実行が怖い**：最初は `apply` のジョブを手動承認（`workflow_dispatch`）にし、慣れたら `main` push に切り替えるという段階的導入もあり。

---

## 7. テストと検証

- `terraform plan` の結果を PR でレビューし、意図しない差分がないかを確認する習慣をつける。
- `terraform show` や `terraform state list` で、リモート state に正しくリソースが登録されているか確認。
- GCS バケットのバージョン履歴をチェックし、state の変更履歴が残っていることを確かめる。
- CI のログで OIDC 認証が成功し、`GOOGLE_APPLICATION_CREDENTIALS` を使わずにアクセスできていることを確認。

---

## 8. セルフチェック（Phase 3 完了の目安）

- [ ] GCS backend が設定され、ローカルに `terraform.tfstate` が残っていない
- [ ] Terraform 実行用のサービスアカウントを作成し、最小権限で動かしている
- [ ] GitHub Actions から OIDC 認証で `terraform plan` が成功し、結果を PR で確認できる
- [ ] `main` へのマージでのみ `terraform apply` が実行される運用フローになっている
- [ ] state のバージョン履歴を確認し、必要に応じて復元できる自信がある

上記のチェックがクリアできれば、Phase 3 の目標である「チームで安全に Terraform を運用するための基礎」が整いました。次の Phase 4 では、Cloud Run や Cloud SQL など代表的な GCP スタックをモジュール化し、実際のアプリ運用に近い構成に挑戦します。

---

## 9. 例えで振り返る（理解の定着）

- **リモートステート**＝現場のホワイトボード。誰が見ても最新の情報が書かれている。
- **サービスアカウント**＝現場監督。人の代わりに権限を持つが、仕事は委任された範囲だけ。
- **OIDC 認証**＝顔認証ゲート。鍵を配らずに「正規のメンバーか？」を判断する仕組み。
- **CI の `plan` コメント**＝工事の設計変更図面。現場に入る前に合意を取るための資料。

ここまで理解できたら Phase 3 の学習は完了です。疑問点があれば README の設計原則を振り返りながら、自分のリポジトリに当てはめてみましょう。
