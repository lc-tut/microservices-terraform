# Authentik・Harbor・k3s（Middleware API の載せ先）を持つ VM。
#
# Authentik と Harbor は Docker Compose、Middleware API は k3s の上に置く。
# 分けているのは lcn-infra-api の deploy/ が素の Kubernetes マニフェストで、
# forward-auth の強制を NetworkPolicy に依存しているため
# （lcn-infra-api/deploy/README.md: NetworkPolicy が無いと誰でもなりすませる）。
# k3s は kube-router 由来の NetworkPolicy コントローラを標準で持つので、
# 追加の CNI を入れなくてもこの前提を満たせる。
#
# Authentik を k3s に入れず Compose のままにしているのは、local/authentik/ と
# 同じ docker-compose.yml をそのまま使うため。ローカルで確認した挙動が
# staging でも同じであることのほうが、配置の統一より価値がある。

resource "google_compute_instance" "platform" {
  name         = "${var.name_prefix}-platform"
  machine_type = var.platform_machine_type
  zone         = var.zone
  tags         = [local.tag]

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.platform_boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.staging.id
    network_ip = google_compute_address.platform_internal.address

    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/scripts/platform-bootstrap.sh.tpl", {
    internal_ip          = var.platform_internal_ip
    devstack_internal_ip = var.devstack_internal_ip
    authentik_version    = var.authentik_version
    # Compose ファイルはリポジトリ側を唯一の元にする（VM 側に二重管理させない）
    authentik_compose            = file("${path.module}/../platform/authentik/docker-compose.yml")
    authentik_secret_key         = local.authentik_secret_key
    authentik_bootstrap_password = local.authentik_bootstrap_password
    authentik_bootstrap_token    = local.authentik_bootstrap_token
    authentik_pg_password        = local.authentik_secret_key
    enable_harbor                = var.enable_harbor
    harbor_version               = var.harbor_version
    harbor_admin_password        = local.harbor_admin_password
    idle_shutdown_minutes        = var.idle_shutdown_minutes
  })

  lifecycle {
    ignore_changes = [metadata_startup_script]
  }
}
