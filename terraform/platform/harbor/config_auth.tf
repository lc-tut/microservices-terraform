# Harbor の認証方式を OIDC（Authentik）に切り替える。
#
# 注意点（terraform/platform/infra/harbor-infra/README.md も参照）:
# - OIDC モードに切り替えても組み込みの admin アカウントはローカル DB 認証で
#   引き続きログインできる（緊急時の抜け道）。
# - OIDC でログインしたユーザーは、docker login/push/pull にはパスワードではなく
#   Harbor UI から発行される CLI Secret を使う（Authentik のパスワードは使えない）。
# - グループ→Harbor admin 権限の自動付与（oidc_admin_group）は、対応する
#   Authentik 側の管理者グループがまだ無いため未設定。将来 circle-admin 相当の
#   Authentik グループができたら oidc_admin_group に設定する。
resource "harbor_config_auth" "oidc" {
  auth_mode         = "oidc_auth"
  primary_auth_mode = var.primary_auth_mode

  oidc_name          = var.oidc_name
  oidc_endpoint      = var.oidc_endpoint
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  oidc_scope         = "openid,profile,email"
  oidc_verify_cert   = var.oidc_verify_cert
  oidc_auto_onboard  = var.oidc_auto_onboard
  oidc_user_claim    = var.oidc_user_claim
}
