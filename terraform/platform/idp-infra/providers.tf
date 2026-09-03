# OpenStack 認証は local/clouds.yaml（OS_CLIENT_CONFIG_FILE）の cloud 名で行う。
# 既定の "polaris-admin" は Kolla-Ansible の admin をパスワード認証で lc-dev
# プロジェクトにスコープしたエントリ（application credential は他プロジェクトへ
# 越境できないため）。認証情報の出所・失効管理は
# local/AUTHENTIK-IDP-CREDENTIALS.md を参照。
provider "openstack" {
  cloud = var.os_cloud
}
