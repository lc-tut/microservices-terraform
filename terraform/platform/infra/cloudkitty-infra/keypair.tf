# 実機確認（2026-09-04）: 既存の CloudKitty VM を新規作成せず import して継続する
# ことにしたため、その VM が使っている既存 keypair "ck-polaris" を data 参照
# する（idp-infra/keypair.tf と同じ理由・同じパターン。tls_private_key は
# terraform import に対応しておらず、既存の秘密鍵と安全に同期できないため）。
# 秘密鍵は local/polaris/ck_key（.gitignore 済み）を使う。
data "openstack_compute_keypair_v2" "cloudkitty" {
  name = "ck-polaris"
}
