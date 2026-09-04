resource "tls_private_key" "harbor" {
  algorithm = "ED25519"
}

resource "openstack_compute_keypair_v2" "harbor" {
  name       = "harbor-infra"
  public_key = tls_private_key.harbor.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.harbor.private_key_openssh
  filename        = "${path.module}/.ssh/harbor"
  file_permission = "0600"
}
