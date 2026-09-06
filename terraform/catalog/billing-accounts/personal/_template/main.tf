# デフォルト（lc-micro・予算上限なし）から変更する場合のみこのディレクトリを作成する。
#
# 08-billing.md の元の設計は `data "lc_cloud_personal_organization"`（独自
# 「Organization」概念。project + 予算上限 + Credit 残高）+ `lc_cloud_budget`
# リソースを使う想定だった。この Organization データモデルは Keystone にも
# CloudKitty にも存在せず自前実装が要る（Middleware API 側、未着手）ため、
# ここでは素の Keystone project 参照 + クォータ設定のみを行う。
# 予算・Credit 残高の管理は Phase 6 以降の課題（16-implementation-phases.md）。
#
# 個人 project の実体は `platform/members/` が台帳から作る。ここはその
# project のクォータを既定から変えたい人だけが作る任意のディレクトリ。
#
# name だけで引くと、同名の project が別 domain にあった場合にそちらを
# 引き当てて、無関係な project のクォータを書き換えてしまう。
# domain_id を必ず指定すること。
data "openstack_identity_project_v3" "this" {
  name      = "user-${replace(var.lcn_id, "_", "-")}"
  domain_id = "default"
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.openstack_identity_project_v3.this.id
  tier       = var.quota_tier

  quota_override = var.quota_override
}
