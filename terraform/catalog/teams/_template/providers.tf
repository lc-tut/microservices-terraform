# OpenStack 認証は admin 権限が要る（プロジェクト作成のため）。
# CI では専用のサービスユーザー（admin 権限）の application credential を
# 使う想定。terraform/platform/openstack/network/ 等と同じ理由・同じ既定値。
provider "openstack" {
  cloud = var.os_cloud
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
  # AUTHENTIK_URL / AUTHENTIK_TOKEN 環境変数でも設定可
}
