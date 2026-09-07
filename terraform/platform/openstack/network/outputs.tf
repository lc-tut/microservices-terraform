# 外部ネットワークの ID（catalog/projects/ 等が data 参照する想定）。
# VPC Gateway ルータ・subnetpool はこのスタックでは管理しない（手動運用に移行）。
output "external_network_id" {
  value = data.openstack_networking_network_v2.external.id
}
