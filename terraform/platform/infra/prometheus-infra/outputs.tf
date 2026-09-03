output "floating_ip" {
  value = openstack_networking_floatingip_v2.prometheus.address
}

output "prometheus_url" {
  value       = "http://${openstack_networking_floatingip_v2.prometheus.address}:9090/api/v1"
  description = "cloudkitty-infra の var.prometheus_url にそのまま渡す値"
}

output "ssh_private_key_path" {
  value = local_sensitive_file.ssh_private_key.filename
}
