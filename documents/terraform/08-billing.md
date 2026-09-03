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

デフォルトクォータは `terraform/platform/openstack/quotas/` で管理者が設定します（OpenStack グローバルデフォルト）。
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
| デフォルトクォータ | `lc-micro`（`platform/openstack/quotas/` で設定） |
| カスタマイズ | `catalog/billing-accounts/personal/<username>/` を作成して PR（管理者承認） |
| 無効化 | メンバーを `alumni/` に移動した時点で apply → 自動無効化 |

### チーム請求アカウント

| 項目 | 内容 |
|---|---|
| 作成タイミング | チーム作成時に LC-Cloud プロジェクトを自動作成 |
| オーナー | 申請チーム（複数チームの共同参照も可） |
| 共有 | **可**。複数チームやプロジェクトが同一アカウントを参照できる |
| デフォルトクォータ | `lc-small`（`platform/openstack/quotas/` で設定） |
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

> **注意（実装との乖離・2026-09-03 調査）**: `lc_cloud_personal_organization`・
> `lc_cloud_organization`・`lc_cloud_budget` は**どの Terraform Provider にも
> 存在しません**。「予算上限・Credit 残高を持つ Organization」という概念自体、
> Keystone の project にも CloudKitty にも相当する標準機能が無く、まるごと
> 自前実装が必要です（独自 DB か Middleware API 側での実装を想定。
> 未着手）。同様に「複数のコスト源（OpenStack・Kubernetes 等）を Organization
> 単位で合算する」処理も、CloudKitty 自身は行ってくれないため自前実装が必要です。
> 詳細は `09-costs.md` の同種の注記、および
> `documents/terraform/16-implementation-phases.md` の
> 「[P5] CloudKitty の導入方針」を参照してください。
> 現状 Terraform で実際に操作できるのは CloudKitty の Hashmap レーティング
> ルール（`terraform/platform/openstack/cloudkitty/`・`modules/cloudkitty-service/`、
> 実機検証済み）までで、それより上のクォータ設定（`modules/lc-cloud-quota`）は
> `project_id` があれば動きますが、予算・Organization 周りはこのドキュメントの
> 設計イメージのみです。
>
> **CloudKitty がやってくれる範囲 と 自前実装が要る範囲の線引き**:
>
> | 機能 | CloudKitty で足りる？ | 備考 |
> |---|---|---|
> | メトリクス（使用量）×単価＝金額の計算 | ✅ 足りる | Hashmap ルールとして実装・実機検証済み |
> | OpenStack リソース1種別ごとの金額算出 | ✅ 足りる | `terraform/platform/openstack/cloudkitty/`。採用した collector は環境依存（`terraform/platform/infra/cloudkitty-infra/README.md` 参照） |
> | Kubernetes namespace 単位の金額算出 | ✅ 足りる（別インスタンスとして） | 未着手。Prometheus collector・`scope_attribute=namespace` |
> | 「Organization」という概念（project + 予算上限 + Credit残高） | ❌ 自前実装が要る | Keystone project にも CloudKitty にも該当メタデータが無い。独自 DB か Middleware API 側のデータモデルとして持つ想定 |
> | 複数 CloudKitty インスタンス（OpenStack用・K8s用）の結果を Organization 単位で合算 | ❌ 自前実装が要る | CloudKitty は自分が計算した範囲しか知らず、他インスタンスの結果を横断して見に行く機能が無い。Middleware API 側でのバッチ集計を想定 |
> | 予算 80% 到達で警告・100% 到達で新規作成ブロック | ❌ 自前実装が要る | CloudKitty の `limit.rate` モジュールは単一インスタンス内・単一メトリクスの制御のみで、複数ソース合算後の判定はできない。Middleware API + OpenStack API 連携で実装する想定 |
> | K8s namespace ↔ OpenStack project の対応関係の解決 | ❌ 自前実装が要る | CloudKitty はこの対応関係自体を知らない。「1 project = 1 namespace（同名）」等の運用規約をどこかのコードで解決する必要がある（Prometheus の relabel 設定 or Middleware API 側のマッピングテーブル） |
>
> つまり CloudKitty は表の上2行（金額計算そのもの）だけを担い、それより上の
> 「予算・Organization」という集計・管理レイヤーは丸ごと未着手です。

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
terraform/platform/openstack/quotas/ の OpenStack グローバルデフォルトを変更して PR
→ 管理者承認 → apply
→ catalog/billing-accounts/ で個別設定していないすべてのアカウントに反映
```
