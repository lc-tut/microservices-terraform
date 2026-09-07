# keypair は OpenStack(Nova)側で生成・管理する。public_key を渡さないと Nova が
# 鍵ペアを生成し、秘密鍵(private_key)を返す。秘密鍵は state に保存され、SSH 用に
# local_sensitive_file で .ssh/ 配下へ 0600 で書き出す（.gitignore 済み想定）。
resource "openstack_compute_keypair_v2" "prometheus" {
  name = "prometheus-infra"
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = openstack_compute_keypair_v2.prometheus.private_key
  filename        = "${path.module}/.ssh/prometheus"
  file_permission = "0600"
}
