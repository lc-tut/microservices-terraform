output "openstack_project_id" {
  description = "catalog/projects/ が参照する OpenStack（Keystone）project ID"
  value       = openstack_identity_project_v3.this.id
}

output "authentik_group_id" {
  value = authentik_group.this.id
}

output "quota_tier" {
  value = module.quota.tier
}
