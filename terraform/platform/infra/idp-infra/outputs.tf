output "floating_ip" {
  description = "Authentik VM の Floating IP"
  value       = openstack_networking_floatingip_v2.authentik.address
}

output "authentik_url" {
  description = "terraform/platform/idp/ の AUTHENTIK_URL / provider url に設定する値"
  value       = "http://${openstack_networking_floatingip_v2.authentik.address}:9000"
}

output "authentik_token" {
  description = "起動時に発行される akadmin API トークン（AUTHENTIK_TOKEN / GitHub Secret 用）"
  value       = random_id.bootstrap_token.hex
  sensitive   = true
}

output "authentik_akadmin_password" {
  description = "akadmin（ユーザー名 akadmin、既定メール root@example.com）の初期ログインパスワード"
  value       = random_password.bootstrap_password.result
  sensitive   = true
}

output "ssh_command" {
  description = "keypair.tf 参照: 秘密鍵は Terraform 管理（local_sensitive_file.ssh_private_key が .ssh/authentik_idp に生成）"
  value       = "ssh -i ${local_sensitive_file.ssh_private_key.filename} rocky@${openstack_networking_floatingip_v2.authentik.address}"
}

output "ssh_private_key_path" {
  description = "生成された秘密鍵ファイルのパス"
  value       = local_sensitive_file.ssh_private_key.filename
}

output "instance_id" {
  value = openstack_compute_instance_v2.authentik.id
}
