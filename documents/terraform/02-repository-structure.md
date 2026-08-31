# リポジトリ構造・3層アクセスモデル

## 3層アクセスモデル

本リポジトリはフォルダ単位で権限を分離した 3 層構造を採用します。

```text
🔴 Tier 1: platform/      管理者・高権限のみ操作可
🟡 Tier 2: catalog/       権限者が編集、誰でも PR 提出可
🟢 Tier 3: workspaces/    チーム・個人に紐づいた自由空間
```

---

## フォルダ構成

```text
microservices-terraform/
│
├── terraform/                         # Terraform 実装一式
│   ├── platform/                      # 🔴 Tier 1：管理者のみ
│   │   ├── idp/                       # Authentik 全体設定（フラット構成。サブディレクトリは無く、
│   │   │   │                          #   enrollment.tf / recovery.tf / annual_renewal.tf /
│   │   │   │                          #   policy_*.tf / provider_*.tf 等がプレフィックス命名で並ぶ）
│   │   ├── members/                   # メンバーライフサイクル管理（active/ob-og/alumniの3層）
│   │   │   ├── active/
│   │   │   │   ├── grad-2027/         # 2027年度卒業予定コホート
│   │   │   │   │   ├── members.yaml              # 管理者: id・role（平文 OK）
│   │   │   │   │   ├── members_secrets.yaml.enc  # 管理者: email・student_id（SOPS 暗号化）
│   │   │   │   │   └── auto-gen-members.yaml     # Bot: username・display_name（enrollment後・平文）
│   │   │   │   └── grad-2026/         # 2026年度卒業予定コホート
│   │   │   │       ├── members.yaml
│   │   │   │       ├── members_secrets.yaml.enc
│   │   │   │       └── auto-gen-members.yaml
│   │   │   ├── ob-og/                 # 卒業後も連絡を継続するOB/OG（同じ grad-XXXX/ 構成、
│   │   │   │                          #   ただし auto-gen-members.yaml.enc 等はSOPS暗号化
│   │   │   │                          #   ＝ lcn_xxxxxx 以外の個人情報を匿名化。.sops.yaml 参照）
│   │   │   ├── alumni/                # 卒業・退会済みで連絡不要なメンバー（ob-og と同じ暗号化方針）
│   │   │   └── auto-gen-github-usernames.yaml  # Bot: GitHub username マップ（OAuth連携時、平文・全体共通）
│   │   ├── network/                   # VPC Gateway・外部ネットワーク・subnetpool
│   │   │   ├── gateway.tf             # VPC Gateway ルーター
│   │   │   ├── subnetpool.tf          # IP 帯域マスタープール
│   │   │   └── external_network.tf    # 外部ネットワーク・RBAC
│   │   ├── images/                    # ベース VM イメージ管理
│   │   │   └── main.tf                # SSH CA 組み込み済みイメージ
│   │   ├── quotas/                    # LC-Cloud クォータティア定義
│   │   │   └── main.tf
│   │   └── github/                    # GitHub Organization 設定
│   │       ├── teams.tf               # GitHub Teams 定義
│   │       ├── branch_protection.tf   # ブランチ保護・PR 承認ルール
│   │       └── codeowners.tf          # CODEOWNERS 自動生成
│   │       # GitHub Org メンバーの個々の所属管理（auto-gen から取得）は
│   │       # このディレクトリではなく terraform/platform/members/github_memberships.tf 側
│   │
│   ├── catalog/                       # 🟡 Tier 2：権限者が編集、誰でも PR 可
│   │   ├── billing-accounts/          # 請求アカウント（クォータ・予算の管理単位）
│   │   │   ├── personal/              # 個人請求アカウント（非共有・カスタム可）
│   │   │   │   ├── _template/
│   │   │   │   ├── alice/
│   │   │   │   └── bob/
│   │   │   └── teams/                 # チーム・共有請求アカウント
│   │   │       ├── _template/
│   │   │       ├── web-shared/        # web チームと配下プロジェクトで共有
│   │   │       └── infra/             # infra チーム専用
│   │   │
│   │   ├── teams/                     # チームの登録・定義（Authentik グループ）
│   │   │   ├── _template/             # 新チーム作成テンプレート（コピーして使う）
│   │   │   │   ├── authentik.tf
│   │   │   │   ├── members.yaml       # チームメンバーの username リスト
│   │   │   │   ├── variables.tf       # billing_account_id（省略可）
│   │   │   │   └── outputs.tf
│   │   │   ├── infra/
│   │   │   │   ├── authentik.tf       # Authentik グループ定義
│   │   │   │   ├── members.yaml       # チームメンバーの username リスト
│   │   │   │   ├── variables.tf
│   │   │   │   └── outputs.tf         # 他スタックが参照する ID など
│   │   │   └── web/
│   │   │       ├── authentik.tf
│   │   │       ├── members.yaml
│   │   │       ├── variables.tf
│   │   │       └── outputs.tf
│   │   │
│   │   └── projects/                  # プロジェクトの登録・定義
│   │       ├── _template/             # 新プロジェクト作成テンプレート（コピーして使う）
│   │       │   ├── harbor.tf
│   │       │   ├── lc_cloud.tf        # OpenStack network・subnet・Application Credential・DNS zone
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       └── my-product/
│   │           ├── harbor.tf          # Harbor registry
│   │           ├── lc_cloud.tf        # OpenStack network・subnet・Application Credential・DNS zone
│   │           ├── variables.tf
│   │           └── outputs.tf
│   │
│   ├── workspaces/                    # 🟢 Tier 3：チーム・個人の自由空間
│   │   ├── teams/
│   │   │   ├── infra/                 # infra チームが自由に管理
│   │   │   └── web/
│   │   └── projects/
│   │       └── my-product/            # プロジェクトオーナーが自由に管理
│   │
│   └── modules/                       # 🔴 Tier 1 扱い（管理者が管理）
│       ├── authentik-user/            # Authentik ユーザー作成
│       ├── authentik-group/           # Authentik グループ作成
│       ├── authentik-flow/            # Authentik フロー定義
│       ├── lc-cloud-organization/     # OpenStack プロジェクト + クォータ
│       ├── lc-cloud-quota/            # クォータティア定義
│       ├── harbor-project/            # Harbor プロジェクト + RBAC
│       ├── lc-vm/                     # VM + ボリューム + SG（Workspace 向け便利モジュール）
│       ├── lc-k8s-app/               # K8s PVC + Secret + ConfigMap
│       ├── lc-object-bucket/          # Swift コンテナ + CORS / lifecycle
│       ├── lc-db/                     # Trove DB インスタンス + ユーザー
│       └── lc-dns-record/             # DNS レコード（ゾーンを data で自動参照）
│
├── scripts/
│   └── sync-mail-aliases.sh           # Mailu エイリアス同期（Terraform 外・State なし）
├── documents/                         # 設計ドキュメント
└── .github/                           # Actions・CODEOWNERS
```

---

## CODEOWNERS 設計

承認権限の管理は Tier ごとに仕組みを使い分けます。詳細は `10-roles-and-permissions.md` を参照してください。

| Tier | パス | 承認者 | 管理方法 |
|------|------|--------|---------|
| 🔴 Tier 1 | `terraform/platform/` `terraform/modules/` | `@org/circle-admin` のみ | `.github/CODEOWNERS` に静的定義 |
| 🟡 Tier 2 | `terraform/catalog/` 各エントリ | 管理者 + チームリードまたは本人 | `terraform-provider-codeowners` が apply 時に自動更新 |
| 🟢 Tier 3 | `terraform/workspaces/` | `@org/all-leads`（デフォルト）または `.codeowners` で個別指定 | `codeowners-plus` が per-directory `.codeowners` を強制 |

---

## 操作別フロー

| 操作 | フォルダ | Tier | PR 提出者 | 承認者 |
|------|---------|------|----------|-------|
| メンバー追加・削除 | `terraform/platform/members/` | 🔴 | circle-admin / tech-lead | circle-admin / tech-lead |
| IdP フロー・ポリシー変更 | `terraform/platform/idp/` | 🔴 | circle-admin / tech-lead / lc-cloud-infra | circle-admin / tech-lead / lc-cloud-infra |
| クォータティア定義変更 | `terraform/platform/quotas/` | 🔴 | circle-admin / tech-lead / lc-cloud-infra | circle-admin / tech-lead / lc-cloud-infra |
| GitHub Org 設定変更 | `terraform/platform/github/` | 🔴 | circle-admin / tech-lead / lc-cloud-platform | circle-admin / tech-lead / lc-cloud-platform |
| モジュール変更 | `terraform/modules/` | 🔴 | circle-admin / tech-lead / lc-cloud-platform | circle-admin / tech-lead / lc-cloud-platform |
| 個人請求アカウントのカスタマイズ | `terraform/catalog/billing-accounts/personal/<name>/` | 🟡 | 本人 [PR] | circle-admin / lc-cloud-infra |
| チーム請求アカウントのカスタマイズ | `terraform/catalog/billing-accounts/teams/<name>/` | 🟡 | team-lead [PR] | circle-admin / lc-cloud-infra |
| 新チーム作成申請 | `terraform/catalog/teams/` | 🟡 | 誰でも [PR] | circle-admin / lc-cloud-platform |
| 新プロジェクト作成申請 | `terraform/catalog/projects/` | 🟡 | 誰でも [PR] | circle-admin / lc-cloud-platform / team-lead（自チーム） |
| プロジェクト内設定変更 | `terraform/workspaces/<name>/` | 🟢 | CODEOWNERS に含まれる人 | CODEOWNERS 次第 |

---

## State 管理

State はスタック（実行単位）ごとに独立したファイルで管理します。
異なるスタックは state ファイルが別なのでロック競合が起きません。
同一スタックへの同時 apply は以下の 2 層で防ぎます。

| Layer | 仕組み | 役割 |
|-------|--------|------|
| 1 | GitHub Actions `concurrency` | 同じスタックへの apply をキューイングし同時実行させない |
| 2 | Terraform state ロック（Ceph RGW） | Layer 1 をすり抜けても二重書き込みをブロック |

```text
# State ファイルのパス例
terraform/platform/members/         → tfstate/terraform/platform/members/terraform.tfstate
terraform/catalog/teams/infra/      → tfstate/terraform/catalog/teams/infra/terraform.tfstate
terraform/catalog/projects/foo/     → tfstate/terraform/catalog/projects/foo/terraform.tfstate
terraform/workspaces/foo/           → tfstate/terraform/workspaces/foo/terraform.tfstate
```

各スタックの `backend.tf` は以下のテンプレートをコピーして `key` のみ変更します。
`use_lockfile = true`（Terraform 1.10+）により DynamoDB 不要で S3 条件付き書き込みによる
state ロックが有効になります。Ceph RGW はこの条件付き書き込みをサポートしています。

```hcl
# backend.tf（各スタックに配置）
terraform {
  backend "s3" {
    bucket   = "linuxclub-tfstate"
    key      = "tfstate/<スタックパス>/terraform.tfstate"
    endpoint = "https://s3.lc-cloud.example.internal"
    region   = "us-east-1"   # S3 互換では dummy 値

    # State ロック（DynamoDB 不要・Ceph RGW 対応）
    use_lockfile = true

    force_path_style            = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
```

---

## CI/CD（GitHub Actions）

### PR 時（plan）

1. 変更されたフォルダを自動検出
2. 対象フォルダごとに `terraform plan` を実行
3. 実行結果を PR コメントに投稿
4. CODEOWNERS の承認 + CI パスが merge 条件

### merge 時（apply）

1. main ブランチへのマージをトリガー
2. 変更されたフォルダごとに `terraform apply` を実行（手動承認ゲートあり）

### セキュリティ

- 認証情報は GitHub Actions Secrets に保管（`AUTHENTIK_TOKEN` / `LC_CLOUD_APP_CRED_*`）
- SOPS の復号鍵は `SOPS_AGE_KEY` として GitHub Actions Secrets に保管
- Workspace（Phase 4）は `catalog/projects/` が発行した Access Rules 付き Application Credential のみ使用
