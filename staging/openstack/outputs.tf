output "vpc_gateway_router_id" {
  description = "catalog/projects/<p>/ の vpc_gateway_router_id に渡す"
  value       = openstack_networking_router_v2.vpc_gateway.id
}

output "subnetpool_id" {
  description = "catalog/projects/<p>/ の subnetpool_id に渡す"
  value       = openstack_networking_subnetpool_v2.lc.id
}

output "external_network_name" {
  description = "platform/openstack/network/ の external_network_name に渡す"
  value       = var.external_network_name
}

output "external_network_id" {
  value = data.openstack_networking_network_v2.external.id
}
