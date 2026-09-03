output "ubuntu_image_id" {
  value       = openstack_images_image_v2.ubuntu.id
  description = "catalog/projects/・workspaces/ 側が openstack_compute_instance_v2.block_device.uuid 等に渡す ID"
}

output "ubuntu_image_name" {
  value = openstack_images_image_v2.ubuntu.name
}

output "ssh_ca_public_key_openssh" {
  value       = tls_private_key.ssh_ca.public_key_openssh
  description = "VM 側 sshd の TrustedUserCAKeys に設定する CA 公開鍵。lc-vm 等の cloud-init から参照する想定"
}

output "ssh_ca_private_key_openssh" {
  value       = tls_private_key.ssh_ca.private_key_openssh
  description = "証明書署名用の CA 秘密鍵。Phase 6 Middleware API 以外には渡さない"
  sensitive   = true
}
