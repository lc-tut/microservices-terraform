# 05-project-lifecycle.md の元の設計は `modules/lc-cloud-organization` 経由で
# 「LC-Cloud Organization」（project + 予算上限 + Credit 残高を持つ独自概念）を
# 作る想定だった。この「Organization」データモデルは Keystone にも CloudKitty
# にも存在せず、実現するには Middleware API 側の自前実装が要る
# （08-billing.md 参照、未着手）。そのため、ここでは Organization を経由せず
# 素の Keystone project + クォータ設定のみを行う（[P3] を参照・更新。
# 16-implementation-phases.md）。予算・Credit 残高の管理は Phase 6 以降の課題。
# project 名に team- を付けるのは、個人 project（user-<lcn_id>）と
# 名前空間を分けるため。チーム名とユーザー名は文字種の制約が同じで、
# 接頭辞が無いと同じ domain の中で衝突しうる。
# 参照はほぼ project ID 経由なので、この名前を消費するのは
# catalog/billing-accounts/{teams,personal}/ の data lookup だけ。
resource "openstack_identity_project_v3" "this" {
  name        = "team-${var.team_name}"
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
data "openstack_identity_user_v3" "automation" {
  name = var.automation_username
}

# member ロールの参照は access.tf の data.openstack_identity_role_v3.role_by_name
# （ロール写像表から引く for_each）を共用する。
resource "openstack_identity_role_assignment_v3" "automation_member" {
  project_id = openstack_identity_project_v3.this.id
  user_id    = data.openstack_identity_user_v3.automation.id
  role_id    = data.openstack_identity_role_v3.role_by_name["member"].id
}
