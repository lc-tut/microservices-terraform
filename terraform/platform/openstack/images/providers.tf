# OpenStack 認証は local/clouds.yaml（OS_CLIENT_CONFIG_FILE）の cloud 名で行う。
# terraform/platform/openstack/network/providers.tf と同じ理由・同じ既定値。
provider "openstack" {
  cloud = var.os_cloud
}
