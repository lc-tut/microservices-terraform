output "openstack_project_id" {
  description = "catalog/projects/ が参照する OpenStack（Keystone）project ID"
  value       = openstack_identity_project_v3.this.id
}

output "authentik_group_id" {
  description = "チーム包括グループ（権限は持たない。access.tf のロール別グループを参照）"
  value       = authentik_group.this.id
}

output "quota_tier" {
  value = module.quota.tier
}

output "role_group_names" {
  description = "ロール別グループ名（Authentik / Keystone 共通）。platform/members/ が名前で解決する"
  value       = module.roles.group_names
}

output "role_group_ids" {
  description = "ロール別 Authentik グループの ID"
  value       = { for r, g in authentik_group.role : r => g.id }
}

output "members_by_role" {
  description = "owners.yaml / members.yaml から解決したロール別の lcn_id 一覧"
  value       = local.members_by_role
}

output "team_policy" {
  description = "team.yaml のポリシー。platform/github/ が Branch Protection・CODEOWNERS 生成に使う"
  value       = local.team_policy
}
