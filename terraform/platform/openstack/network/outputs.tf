# catalog/projects/ が data 参照する想定の出力
# （05-project-lifecycle.md の data.openstack_networking_subnetpool_v2.platform /
# data.openstack_networking_router_v2.vpc_gateway に対応するリソース名を出力）。

output "subnetpool_id" {
  value       = openstack_networking_subnetpool_v2.platform.id
  description = "catalog/projects/ が openstack_networking_subnet_v2.subnetpool_id に渡す ID"
}

output "subnetpool_name" {
  value = openstack_networking_subnetpool_v2.platform.name
}

output "vpc_gateway_router_id" {
  value       = openstack_networking_router_v2.vpc_gateway.id
  description = "catalog/projects/ が openstack_networking_router_interface_v2.router_id に渡す ID"
}

output "external_network_id" {
  value = data.openstack_networking_network_v2.external.id
}
