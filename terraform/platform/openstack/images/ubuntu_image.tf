# SSH CA 組み込み済みの Ubuntu 24.04 ベースイメージ。
#
# 「組み込み済み」の実際の意味（重要）: この repo にはまだ Packer 等の
# イメージビルドパイプラインが無いため、Ubuntu 公式の生の cloud image を
# 加工せずそのまま Glance に登録している。SSH CA の信頼設定
# （sshd の `TrustedUserCAKeys`）はイメージファイル自体には焼き込まれておらず、
# このイメージから VM を起動する側（Phase 5 `modules/lc-vm` を想定）が
# cloud-init の user_data で、下記 properties に含めた CA 公開鍵
# （outputs.tf の `ssh_ca_public_key_openssh` と同じ値）を使って起動時に
# 設定する形になる。将来 Packer 化する場合は、この resource を
# `local_file_path`（ビルド済み qcow2）に差し替える。
resource "openstack_images_image_v2" "ubuntu" {
  name             = var.ubuntu_image_name
  image_source_url = var.ubuntu_image_source_url
  web_download     = true

  container_format = "bare"
  disk_format      = "qcow2"
  visibility       = "public"

  min_disk_gb = var.ubuntu_min_disk_gb
  min_ram_mb  = var.ubuntu_min_ram_mb

  properties = {
    os_distro  = "ubuntu"
    os_version = "24.04"
    # lc-vm 等が cloud-init で TrustedUserCAKeys を設定する際に読める
    # よう、CA 公開鍵そのものをイメージのメタデータとしても持たせておく
    # （出力 ssh_ca_public_key_openssh と同じ値。glance image show で確認可能）
    ssh_ca_public_key = tls_private_key.ssh_ca.public_key_openssh
  }
}
