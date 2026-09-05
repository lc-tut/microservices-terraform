output "instance_id" {
  value       = openstack_compute_instance_v2.this.id
  description = "Nova instance UUID"
}

output "instance_name" {
  value = openstack_compute_instance_v2.this.name
}

output "fixed_ip_v4" {
  value       = openstack_compute_instance_v2.this.access_ip_v4
  description = "プロジェクトネットワーク上の internal IP"
}

output "security_group_id" {
  value       = openstack_networking_secgroup_v2.this.id
  description = "追加ルールを別スタックから足したい場合に使う"
}

output "security_group_name" {
  value = openstack_networking_secgroup_v2.this.name
}

output "volume_id" {
  value       = openstack_blockstorage_volume_v3.root.id
  description = "ルートボリューム(boot-from-volume)の Cinder volume UUID"
}
