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
  tags         = [local.tag, "${var.name_prefix}-public"]

  allow_stopping_for_update = true

  # 時刻ベースの起動/停止（daily_start_time / daily_stop_time）
  resource_policies = local.use_schedule ? [google_compute_resource_policy.daily[0].id] : []

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

    access_config {
      nat_ip = local.platform_needs_static_ip ? google_compute_address.platform_external[0].address : null
    }
  }

  metadata_startup_script = templatefile("${path.module}/scripts/platform-bootstrap.sh.tpl", {
    internal_ip          = var.platform_internal_ip
    devstack_internal_ip = var.devstack_internal_ip

    # Compose ファイルはリポジトリ側を唯一の元にする（VM 側に二重管理させない）
    authentik_compose            = file("${path.module}/../platform/authentik/docker-compose.yml")
    authentik_version            = var.authentik_version
    authentik_secret_key         = local.authentik_secret_key
    authentik_bootstrap_password = local.authentik_bootstrap_password
    authentik_bootstrap_token    = local.authentik_bootstrap_token
    authentik_pg_password        = local.authentik_secret_key

    api_compose       = file("${path.module}/../platform/api/docker-compose.yml")
    infra_db_password = local.infra_db_password
    cursor_secret     = local.cursor_secret
    oidc_client_id    = var.oidc_client_id

    publish    = local.publish
    acme_email = var.acme_email
    auth_host  = local.publish ? local.hostnames.auth : ""
    infra_host = local.publish ? local.hostnames.infra : ""
    # 公開しないときは Harbor と OpenStack を IP で指す。
    # /etc/hosts と Caddy の vhost は publish のときだけ作られる
    harbor_host    = local.publish ? local.hostnames.harbor : var.platform_internal_ip
    openstack_host = local.publish ? local.hostnames.openstack : var.devstack_internal_ip

    smtp_host         = var.smtp_host
    smtp_port         = var.smtp_port
    smtp_username     = var.smtp_username
    smtp_password     = var.smtp_password
    smtp_use_tls      = var.smtp_use_tls
    smtp_use_ssl      = var.smtp_use_ssl
    smtp_from_address = var.smtp_from_address

    enable_harbor         = var.enable_harbor
    harbor_version        = var.harbor_version
    harbor_admin_password = local.harbor_admin_password
    idle_shutdown_minutes = local.idle_shutdown_minutes
  })

  lifecycle {
    ignore_changes = [metadata_startup_script]
  }
}
