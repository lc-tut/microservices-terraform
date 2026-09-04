# 05-project-lifecycle.md の元の設計は `modules/lc-cloud-organization` 経由で
# 「LC-Cloud Organization」（project + 予算上限 + Credit 残高を持つ独自概念）を
# 作る想定だった。この「Organization」データモデルは Keystone にも CloudKitty
# にも存在せず、実現するには Middleware API 側の自前実装が要る
# （08-billing.md 参照、未着手）。そのため、ここでは Organization を経由せず
# 素の Keystone project + クォータ設定のみを行う（[P3] を参照・更新。
# 16-implementation-phases.md）。予算・Credit 残高の管理は Phase 6 以降の課題。
resource "openstack_identity_project_v3" "this" {
  name        = var.team_name
  domain_id   = "default"
  description = "LC-Cloud team: ${var.team_name}"
  enabled     = true
}

module "quota" {
  source     = "../../../modules/lc-cloud-quota"
  project_id = openstack_identity_project_v3.this.id
  tier       = var.quota_tier

  quota_override = var.quota_override
}

# openstack_identity_application_credential_v3（catalog/projects/ が発行する
# Workspace CI 用credential）はセルフサービス限定のリソースで、admin が
# 「他プロジェクト用の credential」を代理発行することはできない。作成する
# トークンがそのプロジェクトにスコープされている必要がある。そのため、
# catalog/projects/ 側で `provider "openstack" { tenant_id = ... }` として
# このプロジェクトにスコープしなおせるよう、自動化アカウントに member ロールを
# 事前に付与しておく。
data "openstack_identity_role_v3" "member" {
  name = "member"
}

data "openstack_identity_user_v3" "automation" {
  name = var.automation_username
}

resource "openstack_identity_role_assignment_v3" "automation_member" {
  project_id = openstack_identity_project_v3.this.id
  user_id    = data.openstack_identity_user_v3.automation.id
  role_id    = data.openstack_identity_role_v3.member.id
}
