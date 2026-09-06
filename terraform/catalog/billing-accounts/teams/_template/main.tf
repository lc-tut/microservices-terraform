# デフォルト（lc-small・予算上限なし）から変更する場合のみこのディレクトリを作成する。
# billing-accounts/personal/_template/main.tf と同じ理由で、元の設計にあった
# 「Organization」（`lc_cloud_organization` + `lc_cloud_budget`）は使わず、
# catalog/teams/ が作成した素の Keystone project を参照してクォータのみ変更する。
# name だけで引くと、同名の project が別 domain にあった場合にそちらを
# 引き当てて、無関係な project のクォータを書き換えてしまう。
# domain_id を必ず指定すること（catalog/teams/ が作る project と同じ default）。
data "openstack_identity_project_v3" "this" {
  name      = "team-${var.team_name}"
  domain_id = "default"
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.openstack_identity_project_v3.this.id
  tier       = var.quota_tier

  quota_override = var.quota_override
}
