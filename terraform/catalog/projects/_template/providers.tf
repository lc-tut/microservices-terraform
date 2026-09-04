provider "openstack" {
  cloud = var.os_cloud
}

# openstack_identity_application_credential_v3 はセルフサービス限定
# （admin が他プロジェクト用に代理発行することはできない）ため、
# team_project_id にスコープしなおした別 provider を使う。
# catalog/teams/<team-name>/ が自動化アカウント（var.os_cloud の認証ユーザー）に
# このプロジェクトの member ロールを事前に付与している前提（teams/_template/lc_cloud.tf 参照）。
provider "openstack" {
  alias     = "team_scoped"
  cloud     = var.os_cloud
  tenant_id = var.team_project_id
}
