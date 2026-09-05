output "container_id" {
  value = openstack_objectstorage_container_v1.this.id
}

output "container_name" {
  value = openstack_objectstorage_container_v1.this.name
}

output "container_url" {
  value       = length(local.object_store_endpoints) > 0 ? "${local.object_store_endpoints[0].url}/${openstack_objectstorage_container_v1.this.name}" : null
  description = "Swift public URL（\"<endpoint>/<container>\"）。object-store サービスが見つからない、または var.region に一致する public endpoint が無い場合は null"
}
