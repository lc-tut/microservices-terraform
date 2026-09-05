output "instance_id" {
  value       = openstack_db_instance_v1.this.id
  description = "Trove instance ID"
}

output "instance_name" {
  value = openstack_db_instance_v1.this.name
}

output "addresses" {
  value       = openstack_db_instance_v1.this.addresses
  description = "インスタンスに割り当てられた IP アドレス一覧"
}

output "database_names" {
  value = [for db in openstack_db_database_v1.this : db.name]
}

output "user_names" {
  value = [for u in openstack_db_user_v1.this : u.name]
}
