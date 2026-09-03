# SSH 鍵は Terraform で生成し、秘密鍵をこの root の .ssh/ に書き出す
# （.gitignore 済み）。既存の lc-key（秘密鍵が lc-sv01 の /root にしか無い）は使わない。
resource "tls_private_key" "authentik" {
  algorithm = "ED25519"
}

resource "openstack_compute_keypair_v2" "authentik" {
  name       = "authentik-idp"
  public_key = tls_private_key.authentik.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.authentik.private_key_openssh
  filename        = "${path.module}/.ssh/authentik_idp"
  file_permission = "0600"
}
