resource "tls_private_key" "prometheus" {
  algorithm = "ED25519"
}

resource "openstack_compute_keypair_v2" "prometheus" {
  name       = "prometheus-infra"
  public_key = tls_private_key.prometheus.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.prometheus.private_key_openssh
  filename        = "${path.module}/.ssh/prometheus"
  file_permission = "0600"
}
