# Phase 2 学習ガイド（モジュール化と環境分離）

Phase 1 のゴールである「単一プロジェクトで GCS バケットを作って壊せる」を達成できたら、次のステップは **同じ設計を複数環境に安全に展開する技術** を身につけることです。Phase 2 では以下の 3 点を重点的に学びます。

- **モジュール化**：Terraform のコードを「意図ごとの部品（モジュール）」に分ける
- **環境分離**：`dev` と `prod` で同じモジュールを呼び出しつつ、差分は `tfvars` だけに閉じ込める
- **バージョン管理**：Terraform 本体とプロバイダのバージョンを固定して、将来の差分事故を防ぐ

以下では、初心者でも一歩ずつ進められるようにコンセプト → 例え → 実装手順 → ハマりポイントの順番で解説します。

---

## 1. モジュール化とは何か？

### 1.1 ざっくりイメージ

- Terraform のモジュールは **「設計図の部品箱」** です。
- 例えるなら、レゴの「車パーツ」「家パーツ」のように、いつでも同じ形の部品を取り出せます。
- Phase 1 で書いた `main.tf` のバケット定義を「バケットを作るモジュール」にしておけば、プロジェクトや環境が変わっても同じ部品を使い回せます。

### 1.2 なぜモジュール化が重要？

- **再利用性**：`modules/vpc` を一度作れば、`dev` でも `prod` でも `stg` でも同じコードを再利用可能。
- **責務の分離**：意図ごとにフォルダを分けることで、何を変更したいのかが明確になる。
- **レビューとテストが楽**：モジュール単位でレビューでき、変更の影響範囲も読みやすい。
- **バグ発見が早い**：1 つのモジュールを dev で検証 → 問題なければ prod へ、というフローが取りやすい。

### 1.3 モジュールの最低構成

```
modules/
  vpc/
    main.tf        # リソースを定義する
    variables.tf   # 受け取る変数（入力）を定義する
    outputs.tf     # 返す値（出力）を定義する
```

- **`main.tf`**：実際に作るリソースを書く（例：`google_compute_network`、`google_compute_subnetwork`）。
- **`variables.tf`**：モジュールが受け取る値（例：VPC 名、サブネット一覧）。
- **`outputs.tf`**：作成したリソースの ID や self link を他モジュールに渡すために定義。

> 例え：`variables.tf` は「注文書」、`main.tf` は「工場」、`outputs.tf` は「納品書」。

---

## 2. 環境分離の考え方（dev / prod をどうやって同じ構成に保つ？）

### 2.1 ゴールの形

```
repo/
  modules/
    vpc/
      ...
  environments/
    dev/
      main.tf       # modules/vpc を呼び出すだけ
      dev.tfvars    # 環境ごとの値（プロジェクト ID など）
      backend.tf    # 後で Phase 3 で使う GCS backend 用（土台だけ用意しておくと良い）
    prod/
      main.tf
      prod.tfvars
      backend.tf
```

- `modules` 配下に意図ごとの部品が並ぶ。
- `environments/dev`・`environments/prod` は **「どのモジュールをどう組み合わせるか」だけ書くフォルダ**。
- 値の違い（プロジェクト ID・リージョン・CIDR など）は `dev.tfvars` / `prod.tfvars` に閉じ込める。

### 2.2 具体的な読み方

`environments/dev/main.tf`

```
module "vpc" {
  source = "../../modules/vpc"

  name   = "app-vpc-dev"
  subnets = [
    {
      name          = "app-subnet-a"
      ip_cidr_range = "10.10.0.0/24"
      region        = var.region
    }
  ]

  labels = var.labels
}
```

- `source` でモジュールの場所を指定（ローカルパス、Git、Registry でも OK）。
- `name`, `subnets`, `labels` などの引数は、モジュールの `variables.tf` に合わせて渡す。
- `var.region` や `var.labels` は `environments/dev/variables.tf` で宣言し、`dev.tfvars` から値を渡す。

`dev.tfvars`

```
project_id = "myproj-dev"
region     = "asia-northeast1"
labels = {
  env   = "dev"
  owner = "platform"
}
```

`prod.tfvars` では値だけを差し替える（名前・CIDR・ラベルなど）。

### 2.3 なぜ tfvars に差分を閉じ込める？

- **コードと設定値を分離**できるので、環境の違いを一目で把握できる。
- `plan` の差分が「値の違いだけ」になり、構造のズレを防げる。
- 将来、ステージングなど新しい環境を増やすときも `*.tfvars` を追加するだけで済む。

> 例え：モジュールは「家の設計図」、`tfvars` は「どの土地に建てるか」「壁紙の色」といった現場ごとの選択肢。

---

## 3. バージョンのピン止め（required_version / required_providers）

### 3.1 何を固定する？

- Terraform 本体のバージョン：`required_version = "~> 1.9"` のように書いて、1.9 系で固定。
- Provider のバージョン：`google` や `google-beta` など、使用するプロバイダを `~> 6.0` のように指定。

### 3.2 なぜ必要？

- Provider が自動で更新されると、同じコードでも毎回 plan に差分が出たり、予期せぬ挙動になることがある。
- チームで開発する場合、全員が同じバージョンを使うことで再現性を担保できる。

### 3.3 書き方（例）

```
terraform {
  required_version = "~> 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}
```

---

## 4. ハンズオン手順（ステップバイステップ）

以下の手順を順番に進めると、Phase 2 のゴールに到達できます。

### ステップ 0：フォルダの初期構成を作る

```
terraform_handson/
  modules/
    vpc/
      main.tf
      variables.tf
      outputs.tf
  environments/
    dev/
      main.tf
      variables.tf
      dev.tfvars
    prod/
      main.tf
      variables.tf
      prod.tfvars
```

- `variables.tf` は `environments/dev` と `environments/prod` で同じ内容（例えば `project_id`, `region`, `labels`）。
- 後ほど Phase 3 で使えるように `backend.tf` を空で用意しておくと吉（今は中身なしで OK）。

### ステップ 0.5：Compute Engine API を有効化する

VPC やサブネットを作るには **Compute Engine API (`compute.googleapis.com`)** が有効になっている必要があります。まだ ON にしていない場合は、以下のどちらかの方法で必ず有効化してください。

- **方法 A：GCP コンソールで手動有効化（初学者向け・一度だけで OK）**

  1. ブラウザで [Compute Engine API の有効化ページ](https://console.developers.google.com/apis/api/compute.googleapis.com/overview) を開く。
  2. 右上のプロジェクトが `terraform-hands-on-for-gcp` など対象のものになっているか確認。
  3. 「有効にする」ボタンを押す（表示されない場合は既に有効化済みです）。
  4. 1 ～ 2 分ほど待ってから Terraform を再実行。

- **方法 B：Terraform で IaC 化（再現性重視）**

  1. `environments/dev`（および `prod`）の `main.tf` など、プロバイダの近くに次のリソースを追加する。

  ```terraform
  resource "google_project_service" "compute" {
    project             = var.project_id
    service             = "compute.googleapis.com"
    disable_on_destroy  = false       # 誤って destroy したときに API を OFF にしない安全策
    depends_on          = []          # 初回は Storage 等ほかの API を有効化していれば特に依存不要
  }
  ```

  2. VPC モジュール側のリソースが API 有効化より先に実行されると失敗することがあるため、必要に応じて `module "vpc"` に `depends_on = [google_project_service.compute]` を付けて順序を保証する。
  3. `terraform init` → `plan` → `apply` を再実行し、API が自動的に有効化されることを確認。

> どちらの方法でも構いませんが、**チーム開発では方法 B を推奨**します。Terraform のコードに「API を有効化する」という手順が含まれるため、新しいプロジェクトでも再現性よく同じ環境を構築できます。

### ステップ 1：VPC モジュールを定義する

`modules/vpc/main.tf` のイメージ（細部は自分で調整して OK）：

```
resource "google_compute_network" "this" {
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.project_id
}

resource "google_compute_subnetwork" "this" {
  for_each                 = { for subnet in var.subnets : subnet.name => subnet }
  name                     = each.value.name
  ip_cidr_range            = each.value.ip_cidr_range
  network                  = google_compute_network.this.id
  region                   = each.value.region
  project                  = var.project_id
  private_ip_google_access = true
}
```

- 1 つの VPC に複数サブネットをまとめて定義できるように `for_each` を使用。
- `private_ip_google_access` など、標準的に ON にしたい設定もここで統一。

`modules/vpc/variables.tf` の例：

```terraform
variable "project_id" {
  description = "この VPC を作成する GCP プロジェクト ID"
  type        = string
}

variable "name" {
  description = "VPC の名前（環境ごとに差し替える）"
  type        = string
}

variable "subnets" {
  description = "サブネットの一覧"
  type = list(object({
    name          = string
    ip_cidr_range = string
    region        = string
  }))
}

variable "labels" {
  description = "リソースに付与するラベル"
  type        = map(string)
  default     = {}
}
```

`modules/vpc/outputs.tf` の例：

```
output "network_self_link" {
  value       = google_compute_network.this.self_link
  description = "作成した VPC の self link"
}

output "subnets" {
  value = {
    for name, subnet in google_compute_subnetwork.this :
    name => {
      self_link = subnet.self_link
      ip_cidr   = subnet.ip_cidr_range
      region    = subnet.region
    }
  }
  description = "サブネットごとのメタデータ"
}
```

### ステップ 2：環境側の `main.tf` を書く

- `environments/dev/main.tf` にモジュール呼び出しを書く。
- `providers.tf` を分けたい場合は `environments/dev/providers.tf` を作り、`project` や `region` に変数を渡す。

`environments/dev/main.tf` の例：

```
terraform {
  required_version = "~> 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "vpc" {
  source = "../../modules/vpc"

  project_id = var.project_id
  name       = var.vpc_name
  subnets    = var.subnets
  labels     = var.labels
}
```

`environments/dev/variables.tf` の例：

```
variable "project_id" {
  type        = string
  description = "デプロイ先プロジェクト"
}

variable "region" {
  type        = string
  description = "基本リージョン（サブネットのデフォルトにも利用）"
}

variable "labels" {
  type        = map(string)
  description = "共通ラベル"
}

variable "vpc_name" {
  type        = string
  description = "VPC 名"
}

variable "subnets" {
  type = list(object({
    name          = string
    ip_cidr_range = string
    region        = string
  }))
  description = "サブネット定義"
}
```

`dev.tfvars` の例：

```
project_id = "myproj-dev"
region     = "asia-northeast1"

labels = {
  env   = "dev"
  owner = "platform"
}

vpc_name = "app-vpc-dev"

subnets = [
  {
    name          = "app-subnet-a"
    ip_cidr_range = "10.10.0.0/24"
    region        = "asia-northeast1"
  }
]
```

`prod.tfvars` では `project_id`, `vpc_name`, `subnets`, `labels` だけ値を変えます（例：IP 範囲を広めにする、サブネットを増やすなど）。

### ステップ 3：`terraform init` → `plan` → `apply`

```
cd environments/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

- `plan` の差分を読み、`create` されるリソースが想定通りか確認。
- 問題なければ `apply`。デフォルトでは `y` の入力で実行。

### ステップ 4：`prod` 環境でも同じモジュールを呼び出す

```
cd ../prod
terraform init
terraform plan -var-file=prod.tfvars
```

- `prod` の `plan` を見て、`dev` と `prod` の違いが値（名前や CIDR）だけになっているか確認。
- もし構造が違う差分が出たら、モジュール側のコードが環境ごとに条件分岐していないか、`tfvars` で指定していない値があるかをチェック。

---

## 5. よくあるハマりポイントと対策

- **`source` パスの書き間違い**：`../../modules/vpc` のように相対パスを正しく指定する。IDE の補完を活用する。
- **変数名のズレ**：モジュール（`modules/vpc/variables.tf`）と環境側（`environments/dev/main.tf`）の変数名が一致しているか確認。
- **`for_each` でのキー重複**：サブネット名は環境内で一意にする。ユニークな `name` を用意する。
- **`plan` での差分が多すぎる**：モジュール内で `count` や `for_each` の条件が環境ごとに変わるロジックになっていないか見直す。
- **ラベルの付け忘れ**：共通ラベルを `tfvars` にまとめておくと追跡が楽。運用上、`env` と `owner` は必須にするチームが多い。

---

## 6. 理解を深めるための追加ヒント

- **モジュールのテスト**：まず dev だけで apply → 動作確認 → prod へ展開、という流れを習慣にする。
- **命名規則の統一**：`{service}-{env}-{用途}` などチームでルールを決めると `tfvars` の差分も読みやすい。
- **Terraform Registry のモジュール**：公式やコミュニティ製のモジュールも同じ構造（`main.tf`/`variables.tf`/`outputs.tf`）なので、読みやすくなる。
- **`terraform-docs`**：Phase 5 で詳しく触れるが、モジュールの入出力を自動ドキュメント化できるツール。Phase 2 の時点で軽く存在だけ知っておくと後で楽。

---

## 7. ゴールチェックリスト（セルフテスト）

- [ ] `modules/vpc` を作り、`dev`/`prod` から同じモジュールを呼び出せた
- [ ] `terraform plan` の差分が「値の違いだけ」になった
- [ ] `required_version` と `required_providers` を設定した
- [ ] `tfvars` を使って環境ごとの値を切り分けできた

上記ができれば Phase 2 の学習目標は達成です。次の Phase 3 では、この構成に**リモートステート（GCS Backend）** と **CI/CD** を組み合わせ、チームで安全に使うための基盤を整えていきます。

---

## 8. もしつまづいたら（FAQ & 例え集）

- **モジュールって結局何？**
  - → レゴの部品。1 回作ったら色だけ変えて何度も使える。
- **`tfvars` の役割は？**
  - → 設計図の空欄に現場ごとの情報を記入する「記入シート」。
- **`required_providers` を書き忘れると？**
  - → 誰かがプロバイダを更新したときに差分地獄が起きる。「使用する工具の型番を全員で揃える」イメージ。
- **`for_each` が難しい**
  - → Excel の `SUBTOTAL` やプログラミングの `for` 文と同じく「リストの要素ごとに処理する」だけ。キー重複に気をつける。
- **`plan` が長くて読めない**
  - → `terraform plan -var-file=dev.tfvars | less` や `terraform plan -out=plan.out` → `terraform show plan.out` で落ち着いて読む。差分が大きすぎるときは `diff` と同じで焦らず原因を切り分ける。

---

ここまで理解できたら、Phase 2 の学習ガイドは完了です。次は Phase 3 に向けて、GCS バックエンドや CI/CD の準備を整えていきましょう。困ったときは README のロードマップを再度確認し、わからない用語はケバブ（Google 検索）する癖をつけると学習がスムーズになります。
