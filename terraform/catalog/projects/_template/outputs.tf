output "network_id" {
  value = openstack_networking_network_v2.project.id
}

output "network_name" {
  value = openstack_networking_network_v2.project.name
}

output "subnet_id" {
  value = openstack_networking_subnet_v2.project.id
}

output "app_cred_id" {
  value = openstack_identity_application_credential_v3.workspace_ci.id
}

# GitHub Actions Secret への自動登録はまだ行わない（GitHub Actions 側の
# CI/CD がこの credential を消費する準備がまだできていないため。README 参照）。
# それまでは terraform output -raw app_cred_secret で手動取得して使う。
output "app_cred_secret" {
  value       = openstack_identity_application_credential_v3.workspace_ci.secret
  description = "Workspace CI/CD 用 credential の secret。state にのみ保存され、平文コミットはしない"
  sensitive   = true
}
