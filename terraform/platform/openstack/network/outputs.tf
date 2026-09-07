# catalog/projects/ が -var / tfvars で受け取る想定の出力。

output "subnetpool_id" {
  value       = openstack_networking_subnetpool_v2.platform.id
  description = "catalog/projects/ が openstack_networking_subnet_v2.subnetpool_id に渡す ID"
}

output "subnetpool_name" {
  value = openstack_networking_subnetpool_v2.platform.name
}

output "internal_network_id" {
  value       = openstack_networking_network_v2.internal.id
  description = "platform 自身の VM と個人プロジェクトの VM が乗る共有内部ネットワークの ID"
}

output "internal_network_name" {
  value = openstack_networking_network_v2.internal.name
}

output "internal_subnet_id" {
  value       = openstack_networking_subnet_v2.internal.id
  description = "int-subnet の ID。固定 IP 指定で port を作るときに使う"
}

output "internal_subnet_cidr" {
  value = openstack_networking_subnet_v2.internal.cidr
}

output "internal_router_id" {
  value       = openstack_networking_router_v2.internal.id
  description = "catalog/projects/ が openstack_networking_router_interface_v2.router_id に渡す int-router の ID"
}

output "external_network_id" {
  value = data.openstack_networking_network_v2.external.id
}

output "external_subnet_id" {
  value       = openstack_networking_subnet_v2.external.id
  description = "ext-subnet の ID。Floating IP を特定サブネットから取るときに使う"
}
