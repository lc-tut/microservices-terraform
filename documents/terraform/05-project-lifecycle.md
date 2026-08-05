# チーム・プロジェクトのライフサイクル

## 概要

チームとプロジェクトはそれぞれ独立したライフサイクルを持ちます。
Terraform は**初期セットアップ（箱づくり）**を担い、セットアップ後のアプリケーション運用はチーム・プロジェクトオーナーに完全委任します。

---

## チームのライフサイクル

### チーム作成（catalog/teams/）

メンバーが `_template/` をコピーして PR を作成します。

Terraform が作成するリソース：

| リソース | 内容 |
|---------|------|
| Authentik Group | IdP グループ（SSO 連携のベース） |
| LC-Cloud Organization | デフォルトクォータ（`lc-small`）でプロジェクトを自動作成 |

`outputs.tf` で `organization_id` を公開することで、`catalog/projects/` が
`billing-accounts/` スタックに依存せず billing account を参照できます。

```hcl
# terraform/catalog/teams/_template/outputs.tf
output "organization_id" {
  description = "LC-Cloud Organization ID（catalog/projects/ が参照する）"
  value       = lc_cloud_organization.this.id
}

output "authentik_group_id" {
  value = authentik_group.this.id
}
```

```hcl
# terraform/catalog/teams/_template/authentik.tf
resource "authentik_group" "this" {
  name         = var.team_name
  is_superuser = false
}

resource "lc_cloud_organization" "this" {
  name    = var.team_name
  # クォータカスタマイズが不要な場合はデフォルト（lc-small）が適用される
  # catalog/billing-accounts/teams/<name>/ を作成した場合はそちらが上書きする
}
```

LC-Cloud クォータ・予算をデフォルトから変更したい場合のみ、
`terraform/catalog/billing-accounts/teams/` にエントリを追加します（`08-billing.md` 参照）。

---

## プロジェクトのライフサイクル

### プロジェクト作成（catalog/projects/）

メンバーが `_template/` をコピーして PR を作成します。

Terraform が作成するリソース：

| リソース | 内容 |
|---------|------|
| Harbor Project | `my-product` コンテナレジストリ |
| k8s Namespace | `my-product` Namespace + デフォルト ResourceQuota・NetworkPolicy |
| CD ツール連携 | （TBD） |

billing account は `catalog/teams/<team>/` の remote state から `organization_id` を取得します。
`catalog/billing-accounts/` が存在するかどうかに関係なく参照できます。

```hcl
# terraform/catalog/projects/_template/variables.tf
variable "team_name" {
  type        = string
  description = "所属チーム名（catalog/teams/<team_name>/ に対応）"
}

variable "project_name" {
  type = string
}
```

```hcl
# terraform/catalog/projects/_template/lc_cloud.tf
data "terraform_remote_state" "team" {
  backend = "s3"
  config = {
    bucket   = "linuxclub-tfstate"
    key      = "tfstate/terraform/catalog/teams/${var.team_name}/terraform.tfstate"
    endpoint = "https://s3.lc-cloud.example.internal"
    region   = "us-east-1"
    force_path_style            = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

module "namespace" {
  source     = "../../../../modules/kubernetes-namespace"
  name       = var.project_name
  quota_tier = "lc-small"

  labels = {
    "lc-cloud/team"             = var.team_name
    "lc-cloud/billing-account" = data.terraform_remote_state.team.outputs.organization_id
  }
}
```

---

## アプリケーションデプロイのフロー（Terraform 管理外）

Terraform によるセットアップ完了後、デプロイはチームが完全に自走します。
デプロイフローの詳細（CI ツール・CD ツール）は選定中（TBD）です。

**このリポジトリ（Terraform）はデプロイフローに一切関与しません。**

---

## プロジェクトの自由な管理（workspaces/）

作成後、プロジェクトオーナーは `workspaces/my-product/` で追加設定を自由に管理できます。
管理者承認不要で自己完結できます。

```text
terraform/workspaces/my-product/
└── config.tf          # Harbor の追加設定等
```

---

## プロジェクトのアーカイブ

プロジェクトが不要になった場合：

1. `terraform/catalog/projects/<name>/lc_cloud.tf` の `archived = true` を設定して PR
2. 承認後 apply → Namespace を削除
3. Harbor イメージは保持期間ポリシーに従い自動削除
