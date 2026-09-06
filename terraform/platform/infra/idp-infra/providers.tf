# OpenStack 認証は auth_url + OS_* 環境変数で行う。IdP を建てるプロジェクトに
# スコープされた認証情報を渡すこと。この root はプロジェクトを越境しないので
# application credential で足りる。
# 認証情報の出所・失効管理は local/AUTHENTIK-IDP-CREDENTIALS.md を参照。
provider "openstack" {
  auth_url = var.os_auth_url
}
