output "floating_ip" {
  value = openstack_networking_floatingip_v2.cloudkitty.address
}

output "cloudkitty_api_url" {
  value       = "http://${openstack_networking_floatingip_v2.cloudkitty.address}:8889"
  description = "Keystone サービスカタログの rating エンドポイントに登録する URL"
}

output "ssh_command" {
  description = "秘密鍵は Terraform 管理（.ssh/cloudkitty、local_sensitive_file が生成）"
  value       = "ssh -i .ssh/cloudkitty rocky@${openstack_networking_floatingip_v2.cloudkitty.address}"
}

output "ssh_private_key_path" {
  value = local_sensitive_file.ssh_private_key.filename
}
