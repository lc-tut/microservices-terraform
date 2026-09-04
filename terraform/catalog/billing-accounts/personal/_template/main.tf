# デフォルト（lc-micro・予算上限なし）から変更する場合のみこのディレクトリを作成する。
#
# 08-billing.md の元の設計は `data "lc_cloud_personal_organization"`（独自
# 「Organization」概念。project + 予算上限 + Credit 残高）+ `lc_cloud_budget`
# リソースを使う想定だった。この Organization データモデルは Keystone にも
# CloudKitty にも存在せず自前実装が要る（Middleware API 側、未着手）ため、
# ここでは素の Keystone project 参照 + クォータ設定のみを行う。
# 予算・Credit 残高の管理は Phase 6 以降の課題（16-implementation-phases.md）。
#
# 前提の注記: 個人 OpenStack project の自動作成（メンバー入会時）自体、
# 現状 `platform/members/` に実装が無い（08-billing.md が書く「SCIM 連携」も
# 実際には廃止済み・未代替。16-implementation-phases.md [P2] 参照）。
# そのため下記の data lookup は、対応する project が実際に存在する前提でのみ動く。
data "openstack_identity_project_v3" "this" {
  name = var.username
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.openstack_identity_project_v3.this.id
  tier       = var.quota_tier

  quota_override = var.quota_override
}
