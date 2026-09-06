# DevStack VM を他のメンバーに渡すための定義。
#
# 構築済み VM をマシンイメージで複製する方式は採っていません。DevStack は
# 構築時のホスト IP とホスト名を設定ファイル・systemd ユニット・etcd の
# データディレクトリ・Keystone のサービスカタログに焼き込むため、複製すると
# それらを一つずつ書き換える必要があり、書き換え漏れが「一見動いているが
# 一部が複製元を向いている」状態として残ります。
#
# `scripts/bootstrap.sh.tpl` には Trove を動かすための修正が入っており、
# 一から構築しても同じ環境になります。所要 40 分程度で無人実行できます。
#
# 使い方:
#   1. terraform.tfvars に shared_vm_owner を設定して apply
#   2. 構築完了まで待つ（/var/log/gcp-devstack-bootstrap.log で確認）
#   3. SHARING.md の手順でパスワードを入れ替えて引き渡す
#
# 不要になったら shared_vm_owner を空に戻して apply すれば消えます。

resource "google_compute_address" "shared" {
  count  = var.shared_vm_owner == "" ? 0 : 1
  name   = "${var.instance_name}-shared"
  region = var.region
}

resource "google_compute_instance" "shared" {
  count        = var.shared_vm_owner == "" ? 0 : 1
  name         = "${var.instance_name}-shared"
  machine_type = var.machine_type
  zone         = var.zone

  # 複製元と同じタグを付けて、既存の IAP 用ファイアウォールをそのまま効かせる
  tags = ["devstack-harbor"]

  allow_stopping_for_update = true

  advanced_machine_features {
    enable_nested_virtualization = var.enable_nested_virtualization
  }

  boot_disk {
    initialize_params {
      image = var.boot_disk_image
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.devstack.id

    access_config {
      nat_ip = google_compute_address.shared[0].address
    }
  }

  # 渡す相手用に、複製元とは別のパスワードで構築する
  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    devstack_admin_password = var.shared_devstack_admin_password
    harbor_admin_password   = var.shared_harbor_admin_password
    external_ip             = google_compute_address.shared[0].address
    harbor_version          = var.harbor_version
  })

  lifecycle {
    ignore_changes = [metadata_startup_script]
  }
}

# 渡した相手が VM に到達するための IAP トンネル権限。
# var.iap_tunnel_users とは別に管理し、共有をやめるときは
# shared_vm_owner を空にするだけで剥がれるようにしている
resource "google_project_iam_member" "shared_vm_iap" {
  count   = var.shared_vm_owner == "" ? 0 : 1
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${var.shared_vm_owner}"
}

output "shared_vm_external_ip" {
  value       = var.shared_vm_owner == "" ? null : google_compute_address.shared[0].address
  description = "渡す相手に伝える外部 IP"
}

output "shared_vm_credentials" {
  value = var.shared_vm_owner == "" ? null : {
    instance = google_compute_instance.shared[0].name
    zone     = var.zone
    external_ip = google_compute_address.shared[0].address
    openstack_admin_password = var.shared_devstack_admin_password
    harbor_admin_password    = var.shared_harbor_admin_password
  }
  sensitive   = true
  description = "引き渡し用。terraform output -json shared_vm_credentials で取り出す"
}
