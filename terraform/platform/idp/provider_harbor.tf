# Harbor OIDC プロバイダ（Harbor 側の auth_mode=oidc_auth 用）。
# authorization_flow/invalidation_flow の data source は provider_lc_cloud.tf で
# 既に宣言済みのものを再利用する（同じ root module 内なのでファイルを跨いで参照できる）。
#
# client_secret は指定せず Authentik に生成させる（Generated 属性）。
# terraform/platform/harbor/ 側の harbor_config_auth.oidc_client_secret に、この
# リソースの client_secret 出力をそのまま渡す（-var 等で明示的に橋渡しする。
# 本 repo の他の連携先 apply と同じく terraform_remote_state は使わない方針）。

data "authentik_property_mapping_provider_scope" "harbor" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

resource "authentik_provider_oauth2" "harbor" {
  count = var.harbor_url != "" ? 1 : 0

  name               = "Harbor"
  client_id          = "harbor"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      # Harbor の OIDC コールバック先。固定パス（Harbor 側の仕様）。
      url = "${var.harbor_url}/c/oidc/callback"
    },
  ]

  property_mappings = data.authentik_property_mapping_provider_scope.harbor.ids
}

resource "authentik_application" "harbor" {
  count = var.harbor_url != "" ? 1 : 0

  name              = "Harbor"
  slug              = "harbor"
  protocol_provider = authentik_provider_oauth2.harbor[0].id
}
