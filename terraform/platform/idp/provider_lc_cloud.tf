# LC-Cloud OIDC プロバイダ（Keystone フェデレーション認証用）
# lc_cloud_oidc_client_id が設定されている場合のみ作成する

data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "lc_cloud" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

resource "authentik_provider_oauth2" "lc_cloud" {
  count = var.lc_cloud_oidc_client_id != "" ? 1 : 0

  name               = "LC-Cloud"
  client_id          = var.lc_cloud_oidc_client_id
  client_secret      = var.lc_cloud_oidc_client_secret
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://horizon.lc-cloud.example.internal/auth/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://keystone.lc-cloud.example.internal/v3/OS-FEDERATION/protocols/openid/auth"
    },
  ]

  property_mappings = data.authentik_property_mapping_provider_scope.lc_cloud.ids
}

resource "authentik_application" "lc_cloud" {
  count = var.lc_cloud_oidc_client_id != "" ? 1 : 0

  name              = "LC-Cloud"
  slug              = "lc-cloud"
  protocol_provider = authentik_provider_oauth2.lc_cloud[0].id
}
