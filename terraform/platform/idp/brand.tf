# デフォルトブランドに recovery flow を設定する
# これにより POST /api/v3/core/users/{id}/recovery/ がメールを送信できる
data "authentik_brand" "default" {
  domain = "authentik-default"
}

resource "authentik_brand" "default" {
  domain        = data.authentik_brand.default.domain
  default       = true
  flow_recovery = authentik_flow.recovery.uuid
}
