# 請求アカウント管理

## 概要

LC-Cloud 上の請求アカウントはデフォルト設定で自動プロビジョニングされます。
クォータ・予算をデフォルトから変更したい場合のみ `catalog/billing-accounts/` にファイルを追加します。

```text
メンバー登録 / チーム作成
  │
  └─ LC-Cloud プロジェクトが自動作成（デフォルトクォータ適用）
       │
       └─ カスタム設定が必要な場合のみ
            catalog/billing-accounts/<type>/<name>/ を追加して PR
```

デフォルトクォータは `terraform/platform/quotas/` で管理者が設定します（OpenStack グローバルデフォルト）。
クォータティアの詳細は `07-quota.md` を参照してください。

| 種別 | デフォルトティア | デフォルト予算 |
|---|---|---|
| 個人 | `lc-micro` | 5,000 Credits/月 |
| チーム | `lc-small` | 15,000 Credits/月 |

コスト定義・Credit 単価・CloudKitty 設定の詳細は `09-costs.md` を参照してください。

---

## 請求アカウントの種別

### 個人請求アカウント

| 項目 | 内容 |
|---|---|
| 作成タイミング | メンバー入会時に SCIM 連携で LC-Cloud プロジェクトを自動作成 |
| オーナー | Authentik ユーザー ID に紐づく（1人1アカウント） |
| 共有 | **不可**。他のメンバー・チームからの参照を LC-Cloud 側でブロック |
| デフォルトクォータ | `lc-micro`（`platform/quotas/` で設定） |
| カスタマイズ | `catalog/billing-accounts/personal/<username>/` を作成して PR（管理者承認） |
| 無効化 | メンバーを `alumni/` に移動した時点で apply → 自動無効化 |

### チーム請求アカウント

| 項目 | 内容 |
|---|---|
| 作成タイミング | チーム作成時に LC-Cloud プロジェクトを自動作成 |
| オーナー | 申請チーム（複数チームの共同参照も可） |
| 共有 | **可**。複数チームやプロジェクトが同一アカウントを参照できる |
| デフォルトクォータ | `lc-small`（`platform/quotas/` で設定） |
| カスタマイズ | `catalog/billing-accounts/teams/<name>/` を作成して PR（管理者承認） |
| 無効化 | 所属チームがすべてアーカイブされた後、管理者が apply で削除 |

---

## 権限モデル

### 個人アカウントの権限

```text
LC-Cloud (OpenStack)
  └─ Personal Organization
       ├─ owner: {authentik_user_id}   ← 本人のみアクセス可
       └─ shareable: false             ← 他者からの参照を拒否
```

### チームアカウントの権限

```text
LC-Cloud (OpenStack)
  └─ Team Organization
       ├─ members: [team_id, ...]      ← 参照を許可するチーム ID のリスト
       └─ shareable: true
```

- `outputs.tf` で `organization_id` を公開し、複数のチーム・プロジェクトが同一アカウントを参照可
- 各チーム・プロジェクトが参照する請求アカウントは **必ず 1 つ**（`billing_account_id` は単数）

---

## Terraform での実装（カスタマイズ時のみ）

`catalog/billing-accounts/` のファイルはデフォルトから変更が必要な場合のみ作成します。
すでに LC-Cloud 上にプロジェクトが存在するため、`data` ソースで参照します。

### 個人アカウントのカスタマイズ

```hcl
# terraform/catalog/billing-accounts/personal/alice/main.tf
# デフォルト（lc-micro・予算上限なし）から変更する場合のみ作成

data "lc_cloud_personal_organization" "this" {
  username = var.username
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.lc_cloud_personal_organization.this.openstack_project_id
  tier       = var.quota_tier

  quota_override = var.quota_override
}

resource "lc_cloud_budget" "this" {
  count           = var.budget_limit != null ? 1 : 0
  organization_id = data.lc_cloud_personal_organization.this.id
  limit_credits   = var.budget_limit
}
```

```hcl
# terraform/catalog/billing-accounts/personal/alice/variables.tf
variable "username" {
  type = string
}

variable "quota_tier" {
  type    = string
  default = "lc-micro"

  validation {
    condition = contains([
      "lc-micro", "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "有効なティア名を指定してください（07-quota.md 参照）。"
  }
}

variable "quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します。"
  type = object({
    instances            = optional(number)
    cores                = optional(number)
    ram_gb               = optional(number)
    volumes              = optional(number)
    snapshots            = optional(number)
    gigabytes            = optional(number)
    per_volume_gigabytes = optional(number)
    backups              = optional(number)
    backup_gigabytes     = optional(number)
    network              = optional(number)
    subnet               = optional(number)
    port                 = optional(number)
    router               = optional(number)
    floatingip           = optional(number)
    security_group       = optional(number)
    security_group_rule  = optional(number)
  })
  default = {}
}

variable "budget_limit" {
  type        = number
  default     = 5000   # Credits/月（個人デフォルト）
}
```

### チームアカウントのカスタマイズ

```hcl
# terraform/catalog/billing-accounts/teams/infra/main.tf
# デフォルト（lc-small・予算上限なし）から変更する場合のみ作成

data "lc_cloud_organization" "this" {
  name = var.team_name
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.lc_cloud_organization.this.openstack_project_id
  tier       = var.quota_tier

  quota_override = var.quota_override
}

resource "lc_cloud_budget" "this" {
  count           = var.budget_limit != null ? 1 : 0
  organization_id = data.lc_cloud_organization.this.id
  limit_credits   = var.budget_limit
}

output "organization_id" {
  value = data.lc_cloud_organization.this.id
}
```

```hcl
# terraform/catalog/billing-accounts/teams/infra/variables.tf
variable "team_name" {
  type = string
}

variable "quota_tier" {
  type    = string
  default = "lc-small"

  validation {
    condition = contains([
      "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "チーム請求アカウントは lc-small 以上を指定してください（07-quota.md 参照）。"
  }
}

variable "quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します。"
  type = object({
    instances            = optional(number)
    cores                = optional(number)
    ram_gb               = optional(number)
    volumes              = optional(number)
    snapshots            = optional(number)
    gigabytes            = optional(number)
    per_volume_gigabytes = optional(number)
    backups              = optional(number)
    backup_gigabytes     = optional(number)
    network              = optional(number)
    subnet               = optional(number)
    port                 = optional(number)
    router               = optional(number)
    floatingip           = optional(number)
    security_group       = optional(number)
    security_group_rule  = optional(number)
  })
  default = {}
}

variable "budget_limit" {
  type    = number
  default = 15000   # Credits/月（チームデフォルト）
}
```

---

## フォルダ構成

```text
terraform/catalog/billing-accounts/
├── personal/                   # 個人クォータのカスタマイズ（必要な場合のみ）
│   ├── _template/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── alice/                  # デフォルトから変更が必要なメンバーのみ
│       ├── main.tf
│       └── variables.tf
└── teams/                      # チームクォータのカスタマイズ（必要な場合のみ）
    ├── _template/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── infra/                  # デフォルトから変更が必要なチームのみ
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## 管理フロー

### クォータ・予算のカスタマイズ申請

```text
1. _template/ をコピーして catalog/billing-accounts/<type>/<name>/ を作成
2. 変更したい項目（quota_tier / quota_override / budget_limit）のみ設定
3. PR → 管理者承認 → apply
```

### デフォルトクォータの変更（全体に影響）

```text
terraform/platform/quotas/ の OpenStack グローバルデフォルトを変更して PR
→ 管理者承認 → apply
→ catalog/billing-accounts/ で個別設定していないすべてのアカウントに反映
```
