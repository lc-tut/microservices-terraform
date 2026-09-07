# lc-sv01（新クラスタ）には既存 keypair "authentik-idp" が存在しないため新規作成する。
# keypair は OpenStack(Nova)側で生成・管理する。public_key を渡さないと Nova が
# 鍵ペアを生成し、秘密鍵(private_key)を返す。秘密鍵は state に保存され、SSH 用に
# local_sensitive_file で ${path.module}/.ssh/authentik_idp へ 0600 で書き出す（.gitignore 済み想定）。
resource "openstack_compute_keypair_v2" "authentik" {
  name = "authentik-idp"
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = openstack_compute_keypair_v2.authentik.private_key
  filename        = "${path.module}/.ssh/authentik_idp"
  file_permission = "0600"
}
