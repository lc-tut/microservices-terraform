# SSH 認証局（CA）鍵。openstack_compute_keypair_v2（固定鍵ペアの配布）の代わりに、
# メンバーには短命の SSH 証明書を発行する運用にするための鍵基盤
# （12-openstack-resources.md「openstack_compute_keypair_v2 は CLI が SSH 証明書で
# 代替」・13-operation-layers.md 参照）。
#
# 証明書を実際に発行する CLI ツール（Authentik SSO 連携）自体は Phase 6
# Middleware API のスコープでまだ実装されていない。ここで用意するのは
# 土台（CA 鍵ペアと、VM 側にこの CA を信頼させるための公開鍵の受け渡し）まで。
#
# 秘密鍵は Terraform state にのみ保持する。Phase 6 が証明書署名に使う際は
# `terraform_remote_state` でこの state を読む（state アクセス自体が
# 秘密鍵の実質的なアクセス制御になるため、本番 backend の権限管理を厳格にすること）。
resource "tls_private_key" "ssh_ca" {
  algorithm = "ED25519"
}
