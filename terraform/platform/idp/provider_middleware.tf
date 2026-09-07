# Middleware API（lcn-infra-api / lcn-billing-api）用の OIDC プロバイダ。
#
# 14-middleware-architecture.md は当初 Proxy Provider + Outpost（forward-auth）を
# 設計していたが、lcn-infra-api は ADR-0017 で OIDC 経路を実装した。API 自身が
# Bearer の JWT を検証するため、Outpost も、Outpost 以外の経路を塞ぐ
# NetworkPolicy も要らない。ここで作るのは OAuth2/OIDC Provider だけ。
#
# middleware_oidc_client_id が空なら何も作らない（他の連携先と同じ方針）。

# ---------------------------------------------------------------------------
# scope mapping
# ---------------------------------------------------------------------------
# **既定の profile scope に頼らない。** lcn-infra-api は
# 「uid claim の値が台帳の lcn_id であること」を配備条件にしており
# （docs/operations/oidc.md）、その保証は既定の mapping にはない。
# 何を載せるかをここで明示する。
#
# 値の出どころは platform/members/authentik_users.tf の attributes:
#   lcn_id     台帳の不変 ID。email や username を変えても変わらない
#   grants     アドオン権限（18-access-control.md「軸 1」）
resource "authentik_property_mapping_provider_scope" "middleware" {
  count = var.middleware_oidc_client_id != "" ? 1 : 0

  name       = "lc-cloud-middleware"
  scope_name = "lc_cloud"
  description = join(" ", [
    "LC-Cloud の Middleware API に、台帳の lcn_id と",
    "所属グループ名を渡す（lcn-infra-api の uid / groups claim）",
  ])

  expression = <<-PYTHON
    # groups には lc-role-map が決めた**グループ名**をそのまま入れる。
    # lcn-infra-api は右端のハイフンで切って scope とロールを導出するため
    # （team-<t>-owner / user-<id>-owner / proj-<p>-<role>）、
    # ID や表示名に変えてはいけない。
    # 参照: modules/lc-role-map/outputs.tf・18-access-control.md
    return {
        "lcn_id": request.user.attributes.get("lcn_id"),
        "groups": [group.name for group in request.user.ak_groups.all()],
        "grants": request.user.attributes.get("grants", []),
    }
  PYTHON
}

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------
data "authentik_property_mapping_provider_scope" "middleware_standard" {
  managed_list = [
    # sub / preferred_username を出すために要る。
    # email は含めない（lcn-infra-api は PII を読まない設計。
    # docs/design/08-authn-authz.md §7）
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

resource "authentik_provider_oauth2" "middleware" {
  count = var.middleware_oidc_client_id != "" ? 1 : 0

  name      = "LC-Cloud Middleware API"
  client_id = var.middleware_oidc_client_id

  # SPA と CLI から使うため public（client secret を配れない）。
  # PKCE 前提。API 側は client secret を持たない（docs/operations/oidc.md）
  client_type = "public"

  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id

  allowed_redirect_uris = [
    for uri in var.middleware_oidc_redirect_uris : {
      matching_mode = "strict"
      url           = uri
    }
  ]

  property_mappings = concat(
    data.authentik_property_mapping_provider_scope.middleware_standard.ids,
    [authentik_property_mapping_provider_scope.middleware[0].id],
  )

  # issuer をアプリごとに分ける（.../application/o/<slug>/）。
  # API 側の LCN_OIDC_ISSUER はこの形を前提にしている。
  # global にすると .../application/o/ になり、設定と食い違って全要求が 401 になる
  issuer_mode = "per_provider"

  # sub は Authentik 内部の識別子で、台帳の lcn_id とは別物。
  # 主体 ID は上の mapping が載せる lcn_id claim を使う（ADR-0017）
  sub_mode = "hashed_user_id"

  # JWT の所属は発行時点の情報で、権限剥奪は有効期限まで反映されない
  # （ADR-0017「結果」）。短めにして遅れを詰める
  access_token_validity  = "hours=1"
  refresh_token_validity = "days=7"
}

resource "authentik_application" "middleware" {
  count = var.middleware_oidc_client_id != "" ? 1 : 0

  name = "LC-Cloud Console"
  # **slug が issuer の一部になる**（.../application/o/<slug>/）。
  # client_id と揃えておかないと、API 側の設定を組み立てるときに間違えやすい
  slug              = var.middleware_oidc_client_id
  protocol_provider = authentik_provider_oauth2.middleware[0].id
}

output "middleware_oidc" {
  description = <<-EOT
    lcn-infra-api / lcn-billing-api に渡す OIDC 設定。
    issuer のホスト部分は Authentik にどの名前でアクセスしたかで決まるため、
    ここでは組み立てず、staging/gcp の output oidc 側で確定させる。
  EOT
  value = var.middleware_oidc_client_id == "" ? null : {
    audience         = var.middleware_oidc_client_id
    issuer_path      = "/application/o/${var.middleware_oidc_client_id}/"
    uid_claim        = "lcn_id"
    username_claim   = "preferred_username"
    groups_claim     = "groups"
    scope_to_request = "openid profile lc_cloud"
  }
}
