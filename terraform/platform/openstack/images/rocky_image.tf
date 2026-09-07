# Rocky Linux 10 GenericCloud イメージ。
# infra/* の VM スタック（idp-infra / cloudkitty-infra / prometheus-infra /
# harbor-infra）が image 名 `rocky-10` を data 参照するため、ここで web_download で
# 登録する。ubuntu と同じく公式の生 cloud image をそのまま Glance に登録している
# （Packer 等のビルドは未導入）。
#
# 補足: openstackclient CLI の `image create` はこの版だと stdin からのファイル
# アップロードを強制し、データ無しだと 415 で "saving" のまま stuck するため、
# web_download を扱える Terraform provider 経由での登録が確実（ubuntu 実績あり）。
resource "openstack_images_image_v2" "rocky" {
  name             = var.rocky_image_name
  image_source_url = var.rocky_image_source_url
  web_download     = true

  container_format = "bare"
  disk_format      = "qcow2"
  visibility       = "public"

  min_disk_gb = var.rocky_min_disk_gb
  min_ram_mb  = var.rocky_min_ram_mb

  properties = {
    os_distro  = "rocky"
    os_version = "10"
    # ubuntu と同様、CA 公開鍵をメタデータにも持たせる（lc-vm 等が参照可能）
    ssh_ca_public_key = tls_private_key.ssh_ca.public_key_openssh
  }
}
