# チーム・プロジェクトのライフサイクル

## 概要

チームとプロジェクトはそれぞれ独立したライフサイクルを持ちます。
Terraform は**初期セットアップ（ネットワーク・認証情報の払い出し等）**を担い、
セットアップ後のインフラ操作・アプリケーション運用はチーム・プロジェクトオーナーに委任します。

---

## チームのライフサイクル

### チーム作成（catalog/teams/）

メンバーが `_template/` をコピーして PR を作成します。

Terraform が作成するリソース:

| リソース | 内容 |
| --- | --- |
| Authentik Group | IdP グループ（SSO 連携のベース） |
| LC-Cloud Organization | デフォルトクォータでプロジェクトを自動作成 |

`outputs.tf` で `organization_id` を公開し、`catalog/projects/` が参照できるようにします。

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
  name = var.team_name
}
```

LC-Cloud クォータ・予算をデフォルトから変更したい場合のみ、
`terraform/catalog/billing-accounts/teams/` にエントリを追加します（`08-billing.md` 参照）。

---

## プロジェクトのライフサイクル

### プロジェクト作成（catalog/projects/）

メンバーが `_template/` をコピーして PR を作成します。
tech-lead 以上の承認後に CI/CD が自動 apply します。

Terraform が作成するリソース:

| リソース | 内容 |
| --- | --- |
| Harbor Project | コンテナレジストリ |
| OpenStack Project（Keystone） | プロジェクト作成（admin 権限） |
| Project Network | プロジェクト専用 private network |
| Project Subnet | subnetpool から /24 を払い出し |
| Router Interface | VPC Gateway への接続 |
| DNS Zone | `<project>.lc-cloud.example.` |
| Application Credential | Access Rules 付き。Workspace CI/CD 用 |
| GitHub Actions Secret | Application Credential を Workspace に渡す |

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

# プロジェクト専用ネットワーク
resource "openstack_networking_network_v2" "project" {
  name = var.project_name
}

resource "openstack_networking_subnet_v2" "project" {
  name            = var.project_name
  network_id      = openstack_networking_network_v2.project.id
  subnetpool_id   = data.openstack_networking_subnetpool_v2.platform.id
  prefix_length   = 24
}

resource "openstack_networking_router_interface_v2" "project" {
  router_id = data.openstack_networking_router_v2.vpc_gateway.id
  subnet_id = openstack_networking_subnet_v2.project.id
}

# DNS ゾーン
resource "openstack_dns_zone_v2" "project" {
  name  = "${var.project_name}.lc-cloud.example."
  email = "admin@lc-cloud.example"
}

# Workspace CI/CD 用 Application Credential（Access Rules 付き）
resource "openstack_identity_application_credential_v3" "workspace_ci" {
  name        = "${var.project_name}-ci"
  description = "CI/CD credential for ${var.project_name} workspace"
  access_rules = [
    # 詳細は 12-openstack-resources.md を参照
    { method = "POST", path = "/v2.1/servers" },
    { method = "GET",  path = "/v2.1/servers/**" },
    # ...
  ]
}

# Application Credential を Workspace リポジトリの GitHub Secret に保存
resource "github_actions_secret" "app_cred_id" {
  repository      = "microservices-terraform"
  secret_name     = "LC_CLOUD_APP_CRED_ID_${upper(replace(var.project_name, "-", "_"))}"
  plaintext_value = openstack_identity_application_credential_v3.workspace_ci.id
}

resource "github_actions_secret" "app_cred_secret" {
  repository      = "microservices-terraform"
  secret_name     = "LC_CLOUD_APP_CRED_SECRET_${upper(replace(var.project_name, "-", "_"))}"
  plaintext_value = openstack_identity_application_credential_v3.workspace_ci.secret
}
```

```hcl
# terraform/catalog/projects/_template/outputs.tf
output "network_name"  { value = openstack_networking_network_v2.project.name }
output "subnet_name"   { value = openstack_networking_subnet_v2.project.name }
output "dns_zone_id"   { value = openstack_dns_zone_v2.project.id }
output "lb_pool_http_id" {
  value       = openstack_lb_pool_v2.http.id
  description = "Workspace が LB pool member を追加する際に参照する"
}
output "lb_public_ip" { value = openstack_networking_floatingip_v2.lb.address }
```

---

## ワークスペースでの運用（workspaces/）

プロジェクト作成後、`workspaces/projects/<name>/` でインフラを自由に定義します。

### Terraform で定義するもの（長期・本番リソース）

```hcl
# VM を建てる場合
module "app" {
  source    = "../../modules/lc-vm"
  flavor    = "lc-small"
  image     = "ubuntu-24.04-lts"
  user_data = file("cloud-init.yaml")
}

# LB pool に追加（catalog が作成した LB を参照）
data "terraform_remote_state" "catalog" {
  backend = "s3"
  config  = { key = "tfstate/terraform/catalog/projects/my-product/terraform.tfstate", ... }
}

resource "openstack_lb_member_v2" "app" {
  pool_id       = data.terraform_remote_state.catalog.outputs.lb_pool_http_id
  address       = module.app.ip_address
  protocol_port = 8080
}

resource "openstack_dns_recordset_v2" "app" {
  zone_id = data.terraform_remote_state.catalog.outputs.dns_zone_id
  name    = "myapp.lc-cloud.example."
  type    = "A"
  records = [data.terraform_remote_state.catalog.outputs.lb_public_ip]
}
```

### Middleware API / GUI で操作するもの（運用・実験）

- VM の起動・停止・再起動・コンソール・ログ確認
- 実験・開発用の一時 VM 作成（Terraform 管理不要）
- Trove DB の手動バックアップ
- K8s Pod のログ確認・exec・rollout restart

詳細は `13-operation-layers.md` を参照。

### ArgoCD / FluxCD で管理するもの（アプリ）

- Deployment・Service・Ingress
- HPA

---

## プロジェクトのアーカイブ

プロジェクトが不要になった場合:

1. `workspaces/projects/<name>/` の全リソースを削除して PR → apply
2. `catalog/projects/<name>/lc_cloud.tf` を削除 または `archived = true` を設定して PR
3. apply → ネットワーク・DNS ゾーン・Application Credential を削除
4. Harbor イメージは保持期間ポリシーに従い自動削除
