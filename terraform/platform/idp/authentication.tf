# ログイン画面のタイトルを "Welcome to authentik!"（組み込み default-authentication-flow の
# 固定文言）から変更するための独自 authentication flow。
#
# default-authentication-flow は Authentik が blueprint で自動生成・管理するオブジェクトで、
# blueprint 再適用時に title を上書きされる可能性があるため Terraform では直接触らない
# （blueprints/default/flow-default-authentication-flow.yaml 参照）。代わりに独自の flow を
# 作成し、authentik_brand.default.flow_authentication で差し替える。
# ステージ構成は上記 blueprint の内容をそのまま踏襲している（4 ステージ + 2 ポリシー）。

data "authentik_flow" "default_password_change" {
  slug = "default-password-change"
}

resource "authentik_flow" "lc_cloud_authentication" {
  name        = "LC-Cloud Authentication"
  title       = "Welcome to LC-Cloud!"
  slug        = "lc-cloud-authentication"
  designation = "authentication"
  layout      = "stacked"

  # ログインページだけは brand.branding_default_flow_background（flow_background.jpg）
  # ではなく、ワイドロゴを背景に使う
  background = "${local.idp_assets_base_url}/linuxclub_wide_logo.png"
}

resource "authentik_stage_identification" "authentication_id" {
  name = "authentication-identification"

  # "upn" は attributes.upn を照合対象にする特別扱いのキー
  # （authentik/stages/identification/stage.py: "upn" -> "attributes__upn"）。
  # 大学メール（email フィールド）に加えて、将来支給する独自ドメインメールでも
  # ログインできるようにするための受け口。Authentik公式ドキュメント
  # （microsoft-saml連携ガイド）でも「ADと同期しないユーザーはメールアドレスを
  # UPNとして使うのが最も簡単」と案内されている、想定通りの使い方。
  # 独自ドメインメールの発行方式が決まるまでは attributes.upn は誰にも
  # 設定されないため、この行を追加するだけでは何も変わらない（無害）
  user_fields = ["email", "username", "upn"]

  # 連携済みの GitHub/Discord アカウントでのログインボタンを表示する
  # （client_id が空で source 自体が作られていない場合は sources に含めない）
  sources = compact([
    var.github_oauth_client_id != "" ? authentik_source_oauth.github[0].uuid : "",
    var.discord_oauth_client_id != "" ? authentik_source_oauth.discord[0].uuid : "",
  ])
}

resource "authentik_stage_password" "authentication_password" {
  name = "authentication-password"
  backends = [
    "authentik.core.auth.InbuiltBackend",
    "authentik.sources.kerberos.auth.KerberosBackend",
    "authentik.sources.ldap.auth.LDAPBackend",
    "authentik.core.auth.TokenBackend",
  ]
  configure_flow = data.authentik_flow.default_password_change.id
}

resource "authentik_stage_authenticator_validate" "authentication_mfa_validation" {
  name                  = "authentication-mfa-validation"
  not_configured_action = "skip"
  device_classes        = ["static", "totp", "webauthn", "duo", "sms", "email"]
}

resource "authentik_stage_user_login" "authentication_login" {
  name = "authentication-login"
}

# 既にソースログイン等で認証済み（pending_user に backend が付いている）なら
# パスワードステージをスキップする
resource "authentik_policy_expression" "authentication_password_optional" {
  name       = "authentication-password-optional"
  expression = <<-PYTHON
    flow_plan = request.context.get("flow_plan")
    if not flow_plan:
        return True
    return not hasattr(flow_plan.context.get("pending_user"), "backend")
  PYTHON
}

# passwordless(WebAuthn) でログインした場合は MFA 検証ステージをスキップする
resource "authentik_policy_expression" "authentication_mfa_optional" {
  name       = "authentication-mfa-optional"
  expression = <<-PYTHON
    flow_plan = request.context.get("flow_plan")
    if not flow_plan:
        return True
    return not (flow_plan.context.get("auth_method") == "auth_webauthn_pwl")
  PYTHON
}

resource "authentik_flow_stage_binding" "authentication_id" {
  target = authentik_flow.lc_cloud_authentication.uuid
  stage  = authentik_stage_identification.authentication_id.id
  order  = 10
}

resource "authentik_flow_stage_binding" "authentication_password" {
  target               = authentik_flow.lc_cloud_authentication.uuid
  stage                = authentik_stage_password.authentication_password.id
  order                = 20
  re_evaluate_policies = true
}

resource "authentik_policy_binding" "authentication_password_gate" {
  target         = authentik_flow_stage_binding.authentication_password.id
  policy         = authentik_policy_expression.authentication_password_optional.id
  order          = 10
  failure_result = true
}

resource "authentik_flow_stage_binding" "authentication_mfa_validation" {
  target = authentik_flow.lc_cloud_authentication.uuid
  stage  = authentik_stage_authenticator_validate.authentication_mfa_validation.id
  order  = 30
}

resource "authentik_policy_binding" "authentication_mfa_validation_gate" {
  target         = authentik_flow_stage_binding.authentication_mfa_validation.id
  policy         = authentik_policy_expression.authentication_mfa_optional.id
  order          = 10
  failure_result = true
}

resource "authentik_flow_stage_binding" "authentication_login" {
  target = authentik_flow.lc_cloud_authentication.uuid
  stage  = authentik_stage_user_login.authentication_login.id
  order  = 100
}
