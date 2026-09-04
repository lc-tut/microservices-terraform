output "floating_ip" {
  value = openstack_networking_floatingip_v2.harbor.address
}

output "harbor_url" {
  value       = "http://${openstack_networking_floatingip_v2.harbor.address}"
  description = "docker login / Harbor portal URL（var.harbor_hostname を Floating IP に合わせて設定した場合）"
}

output "harbor_admin_password" {
  value       = random_password.harbor_admin.result
  description = "Harbor admin ユーザーのパスワード。GitHub Secrets の HARBOR_ADMIN_PASSWORD に登録する想定（16-implementation-phases.md 参照）"
  sensitive   = true
}

output "ssh_private_key_path" {
  value = local_sensitive_file.ssh_private_key.filename
}
