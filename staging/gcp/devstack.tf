# OpenStack（DevStack）専用 VM。
# platform VM と分けているのは、DevStack のクリーン構築が 40 分前後かかり、
# その間 Authentik と Middleware API まで巻き込んで落ちるのを避けるため。
# n2-standard-8 一台と n2-highmem-4 + e2-standard-4 の二台では計算費がほぼ同額なので、
# 分割による割高はディスクと外部 IP のぶんだけ（月 1,600 円程度）。

resource "google_compute_instance" "devstack" {
  name         = "${var.name_prefix}-devstack"
  machine_type = var.devstack_machine_type
  zone         = var.zone
  tags         = [local.tag]

  allow_stopping_for_update = true

  # DevStack の Nova がこの VM の中でさらに VM を建てるため必須。
  # 無効だと /dev/kvm が現れず virt_type=qemu になり、Trove のゲストイメージは
  # 起動しきらない。N2 系でしか有効にできない（E2 では apply が失敗する）。
  advanced_machine_features {
    enable_nested_virtualization = var.enable_nested_virtualization
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.devstack_boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.staging.id
    network_ip = google_compute_address.devstack_internal.address

    # 外部 IP はエフェメラル。bootstrap 中のパッケージ取得とイメージ取得に要る。
    # 到達は IAP 経由なので、外から直接この IP を開くことはできない
    # （ファイアウォールが IAP レンジのみ許可）。
    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/scripts/devstack-bootstrap.sh.tpl", {
    devstack_admin_password = var.devstack_admin_password
    internal_ip             = var.devstack_internal_ip
    idle_shutdown_minutes   = var.idle_shutdown_minutes
  })

  lifecycle {
    # bootstrap は /opt/lc-staging/.bootstrapped で初回のみ実行に守られており、
    # 構築後の VM にとって起動スクリプトの内容は意味を持たない。
    # 無視しないと、スクリプトを直すたびに構築済みの VM が作り直される。
    ignore_changes = [metadata_startup_script]
  }
}
