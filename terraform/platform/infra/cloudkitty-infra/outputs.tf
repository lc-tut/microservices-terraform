output "floating_ip" {
  value = openstack_networking_floatingip_v2.cloudkitty.address
}

output "cloudkitty_api_url" {
  value       = "http://${openstack_networking_floatingip_v2.cloudkitty.address}:8889"
  description = "Keystone サービスカタログの rating エンドポイントに登録する URL"
}

output "ssh_command" {
  description = "秘密鍵は Terraform 管理外（local/polaris/ck_key、既存ファイルを使う）"
  value       = "ssh -i ../../../../local/polaris/ck_key rocky@${openstack_networking_floatingip_v2.cloudkitty.address}"
}
