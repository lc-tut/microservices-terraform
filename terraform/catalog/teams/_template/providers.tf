# OpenStack 認証は admin 権限が要る（プロジェクト作成のため）。
# 認証情報は OS_* 環境変数で渡す。application credential は作成時のプロジェクトに
# 固定され system スコープのトークンを取れないため、Keystone が enforce_scope で
# 動いている環境ではプロジェクト作成に使えない。その場合は system スコープの
# 認証情報（OS_SYSTEM_SCOPE=all）を渡すこと。
provider "openstack" {
  auth_url = var.os_auth_url
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
  # AUTHENTIK_URL / AUTHENTIK_TOKEN 環境変数でも設定可
}
