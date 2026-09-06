# workspaces/ 側の modules/lc-vm・lc-db に var.network_name として渡す。
# 実体は所属チームのネットワーク（この root では作らない）。
output "network_name" {
  value = data.openstack_networking_network_v2.team.name
}

output "network_id" {
  value = data.openstack_networking_network_v2.team.id
}

output "security_group_id" {
  value       = openstack_networking_secgroup_v2.baseline.id
  description = "ベースライン SG。同じチームネットワーク上の他プロジェクトと分離するため、このプロジェクトの VM は必ずこれを付けて起動する"
}

output "security_group_name" {
  value = openstack_networking_secgroup_v2.baseline.name
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
