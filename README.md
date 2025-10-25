# 目的

このリポジトリは、GCP と Terraform をこれから学ぶ初学者が、実務で通用するレベルまで Terraform を扱えるようになることを狙ったハンズオン教材です。README のロードマップに沿ってフェーズを進めながら、各 `phase_x/guide.md` を参照して学習と実装を進めてください。

**ゴール**

- 同一モジュールを使い、`dev`/`prod` で**差分は入力（変数・tfvars・IAM・配列値）だけ**にする
- チームで安全に回すため、**状態管理・権限・CI** を標準装備にする

**設計原則（ずっと使うチェックリスト）**

1. **モジュール化**：1 リソース=1 ファイルではなく、**1 意図=1 モジュール**（例：vpc、run_service、sql_instance）
2. **環境分離**：`environments/dev` と `environments/prod` に**同一モジュール**を参照させ、`*.tfvars` でだけ差をつける
3. **状態管理**：**GCS バックエンド** or **Terraform Cloud** を使い、state を共有・保護
4. **アイデンティティ**：**Workload Identity Federation(OIDC)** を使って GitHub Actions から**鍵レス**で apply
5. **品質**：`pre-commit`（fmt/validate/tflint/tfsec/terraform-docs）＋ PR レビュー必須
6. **変更の安全性**：`plan` を PR で可視化、`apply`は保護ブランチ＋承認が必要
7. **移行**：GUI 作成済みリソースは **import → HCL 化 → 差分ゼロ**を見てから管理移管

---

# 1. フェーズ別ロードマップ（最短 4〜5 週間版）

## Phase 1（基礎の 30%）：Terraform/GCP の最小セット（1〜2 日）

**学ぶこと**

- Terraform 基本：`providers / resources / variables / outputs / locals / modules`
- `terraform init/plan/apply/destroy` の意味
- GCP の基本：Project / Region / Zone / IAM の粒度、サービス有効化（※Service Usage API は初回だけ手動で ON が必要）

**手を動かす課題**

- ローカルで**単一プロジェクトに 1 個の Cloud Storage バケツ**を作って削除できる

**受け入れ基準**

- `main.tf` だけで GCS バケツを作成 → 削除できる
- `variables.tf` に `project_id`, `region` を定義し、`terraform.tfvars` で値を渡せる

---

## Phase 2（設計の 50%）：モジュールと環境分離（2〜3 日）

**学ぶこと**

- **モジュール**（入力=変数、出力=outputs）
- **同一構成の環境分離**：`dev`/`prod` フォルダ＋ `*.tfvars`
- バージョンピン止め：Terraform 本体・Provider

**手を動かす課題**

- **VPC モジュール**（VPC/サブネット/基本 FW）を作る
- `environments/dev` と `environments/prod` から**同じ VPC モジュール**を呼び出し

**受け入れ基準**

- `dev` と `prod` で `plan` の差分が**タグや名前、CIDR**などの**値だけ**に収まる
- `required_version` と `required_providers` がピン止めされている

**サンプル構成（最終的に近い形）**

```
repo/
  modules/
    vpc/
      main.tf
      variables.tf
      outputs.tf
    run_service/
    sql_instance/
  environments/
    dev/
      main.tf          # modulesを呼ぶだけ
      dev.tfvars
      backend.tf       # GCS backend
    prod/
      main.tf
      prod.tfvars
      backend.tf
  global/
    providers.tf       # 共通プロバイダ設定(必要なら)
  .tflint.hcl
  .terraform-docs.yml
  .pre-commit-config.yaml
```

---

## Phase 3（チーム対応の 70%）：状態管理と CI/CD（3〜4 日）

**学ぶこと**

- **GCS バックエンド**で state 共有（バケット、バージョニング、有効化）
- **IAM の最小権限**（apply 用 SA のみが管理する）
- **GitHub Actions + OIDC** で**鍵レス**認証（`google-github-actions/auth`）

**手を動かす課題**

- `terraform { backend "gcs" {...} }` を `environments/*/backend.tf` に配置
- GitHub Actions で `plan` を PR にコメント、`main` マージで `apply`

**受け入れ基準**

- ローカルで `state` を持たない（`terraform show` で GCS 参照/履歴が見える）
- `plan` が PR で自動出力、`apply` は保護ブランチ＋承認でのみ可能

**最小バックエンド例（GCS）**

```hcl
terraform {
  required_version = "~> 1.9"
  backend "gcs" {
    bucket = "tfstate-<your-project>-prod"
    prefix = "prod"
  }
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
  }
}
provider "google" {
  project = var.project_id
  region  = var.region
}
```

---

## Phase 4（実務レベルの 85%）：代表的 GCP スタックの IaC 化（4〜6 日）

**学ぶこと**

- Cloud Run（最も扱いやすい）
- Cloud SQL（Private IP/接続、めっちゃ差分多いので丁寧に）
- Secret Manager、Artifact Registry、Cloud NAT/Router

**手を動かす課題（推奨パス）**

1. **`vpc`モジュール**（完成済）
2. **`run_service`モジュール**

   - サービス、リビジョン設定（CPU/Memory/concurrency）、Ingress/IAM（呼び出し権限）

3. **`sql_instance`モジュール**

   - Private IP、バックアップ設定、最小構成パラメータ

4. **`secret`モジュール**（アプリ用シークレット注入）

**受け入れ基準**

- `dev` と `prod` が**同一モジュール**で動作
- `dev` で動くアプリを `prod` へ**tfvars 差分だけ**で展開

---

## Phase 5（完成度 100%）：品質・セキュリティ・運用（3〜5 日）

**学ぶこと**

- `pre-commit`（`fmt`/`validate`/`tflint`/`tfsec`/`terraform-docs`）
- 変更プレビュー（`terraform plan -out=planfile` → `show`）
- **ドリフト検出**（`terraform plan` をスケジュール実行、差分通知）
- **ポリシー**：`checkov` or OPA/Conftest で組織ルール（例：Public IP 禁止、ラベル必須）
- **コストガード**：`var.machine_type` や `autoscaling` の上限を環境別に制御

**受け入れ基準**

- PR 時：`lint/scan` が通らないとマージ不可
- 週 1 の自動 `plan` で**手動変更（GUI いじり）**が検知できる

---

# 2. まず作る「最小でも役立つ」サンプル

### A) VPC モジュールの変数（抜粋）

```hcl
variable "name" { type = string }
variable "subnets" {
  type = list(object({
    name          = string
    ip_cidr_range = string
    region        = string
  }))
}
variable "labels" { type = map(string) default = {} }
```

### B) dev/prod の呼び出し例

```hcl
module "vpc" {
  source = "../../modules/vpc"
  name   = "app-vpc"
  subnets = [
    { name = "app-subnet-a", ip_cidr_range = "10.10.0.0/24", region = var.region },
  ]
  labels = var.labels
}
```

### C) dev/prod の `*.tfvars` 例

`dev.tfvars`

```hcl
project_id = "myproj-dev"
region     = "asia-northeast1"
labels = { env = "dev", owner = "platform" }
```

`prod.tfvars`

```hcl
project_id = "myproj-prod"
region     = "asia-northeast1"
labels = { env = "prod", owner = "platform" }
```

---

# 3. チーム開発の運用ルール（短く強い版）

- **ブランチ**：`main` は保護。`feature/*` → PR → `plan` 自動コメント → レビュア承認 → `main` マージ → `apply`
- **権限**：人に Editor を付けない。**CI の Service Account**に最小権限（`roles/viewer`＋必要分だけ）。
- **秘密情報**：平文で `.tfvars` に書かない。**Secret Manager** or GitHub Secrets。
- **変更手順**：GUI で触らない（どうしても触ったら**import**して差分ゼロに戻す）
- **命名 & ラベル**：`{team}-{service}-{env}`、`labels = { env, owner, costcenter }` を統一

---

# 4. 既存（GUI 作成済み）リソースの取り込み

1. リソース ID を調べる
2. まず **空の resource** を HCL に作成（属性は最小）
3. `terraform import` で state に取り込む
4. `terraform plan` で差分を見ながら**HCL 側に属性を追加**
5. `No changes` になったら管理移行完了
   （補助ツール：**terraformer** で下書き HCL を出して整える手もあり）

---

# 5. CI/CD の最低構成（概念だけ掴む）

- GitHub Actions:

  - `auth`：`google-github-actions/auth`（OIDC で SA を**impersonate**）
  - `setup-terraform`：`hashicorp/setup-terraform`
  - `tflint`, `tfsec`, `terraform fmt -check`, `terraform validate`
  - `terraform plan` を PR にコメント、`terraform apply` は `main` のみ

---

# 6. よくある落とし穴（先に知っておく）

- **Provider のバージョン差**で plan が毎回出る → `required_providers` 固定
- **state 分離忘れ**（dev/prod が同じバックエンド prefix） → 必ず prefix/バケット分け
- **並列 apply**（2 人が同時に apply） → CI でのみ apply、ローカル禁止
- **Cloud SQL の破壊的変更** → パラメータ変更はメンテ計画＆バックアップ
- **リージョン縛り** → サービスごとのリージョン制約を最初に確認（Run, SQL, GCS など）

---

# 7. 学習の目安（ざっくりカレンダー）

- **Week 1**：Phase 1–2 完了（VPC をモジュール化、dev/prod を`tfvars`で分離）
- **Week 2**：Phase 3 完了（GCS backend、CI の plan 表示まで）
- **Week 3**：Phase 4 の Cloud Run モジュール実装、dev→prod へ反映
- **Week 4**：Phase 4–5 の SQL/Secrets 追加、pre-commit・tfsec・ドリフト検出

---

# 8. ここまで理解できたら設計 OK（セルフチェック）

- [ ] 同一モジュールを dev/prod で使い回し、差分は `*.tfvars` に閉じ込めた
- [ ] state は GCS（or Terraform Cloud）で共有・保護
- [ ] CI で `plan` が PR に出て、`apply` は保護ブランチ＆承認フロー
- [ ] pre-commit で fmt/validate/tflint/tfsec/docs が自動実行
- [ ] GUI 作成分は import 済み、`plan` が No changes

---

必要なら、このロードマップ用に**スターターリポジトリの雛形**（`modules/vpc`, `environments/dev|prod`, `pre-commit` 設定、GitHub Actions 最小ワークフロー）をその場で書き出します。作ってほしいなら言ってね。

- **学習の進め方**

  - 各 Phase の学びや作業内容は、この README をベースにしながら随時 `phase_x/guide.md` としてハンズオン資料を自作しています。
  - 次のフェーズ用資料が必要になったら、Cursor Agent などの支援ツールに依頼してハンズオンを生成し、その内容をガイドとして追加してください。
  - 参考までに、これまでガイド作成時に使用したプロンプト例を以下にまとめます。

- **参考プロンプト（Cursor Agent 依頼例）**

  - Phase 2 ガイド作成時：

    ```
    terraformの入門のため、@README.md の手順に従って、ハンズオンを通してterraformのインプットをしています。今phase_1が完了しました。

    続いてphase_2に入りたいので、phase_2の学習内容をphase_2/guide.mdに記載してください。学習ガイドを作成する際に、下記のことに気をつけてください。

    terraformを今日から始めた人でもわかりやすいように詳しく、解説してください。 もし難しい概念がある場合、それについてもわかりやすい例えをしながら解説して
    ```
