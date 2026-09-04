output "openstack_project_id" {
  value = data.openstack_identity_project_v3.this.id
}
