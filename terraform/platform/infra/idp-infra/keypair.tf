# 実機確認（2026-09-04）: 元は tls_private_key + openstack_compute_keypair_v2
# (resource) で新規生成する設計だったが、tls_private_key は terraform import に
# 対応しておらず、既に存在する実際の keypair "authentik-idp" と秘密鍵ファイル
# （.ssh/authentik_idp、gitignore 済み・SSH に使用中）を安全に管理下へ移す方法が
# 無かった。誤って再 apply すると新しい鍵で keypair を作り直そうとして
# （keypair の public_key は変更不可のため force-replace になり）既存 VM への
# SSH 経路を壊すリスクがあるため、既存 keypair は data 参照のみに留める
# （terraform/platform/openstack/network/ で ext-net を data 参照のみにしたのと
# 同じ考え方）。
data "openstack_compute_keypair_v2" "authentik" {
  name = "authentik-idp"
}
