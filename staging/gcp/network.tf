# staging 専用の VPC。local/gcp-devstack の devstack-harbor ネットワークとは
# 完全に分離する（同じプロジェクトに同居させるため、名前も範囲も重ねない）。

resource "google_compute_network" "staging" {
  name                    = var.name_prefix
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "staging" {
  name          = var.name_prefix
  network       = google_compute_network.staging.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr
}

# IAP (Identity-Aware Proxy) の TCP フォワーディング元レンジ。
# https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule
locals {
  iap_range = "35.235.240.0/20"
  tag       = var.name_prefix

  publish = var.dns_zone != ""

  hostnames = {
    auth      = "auth.${var.dns_zone}"
    infra     = "infra.${var.dns_zone}"
    harbor    = "harbor.${var.dns_zone}"
    openstack = "openstack.${var.dns_zone}"
  }
}

# SSH は常に IAP 経由のみ。公開設定に関わらず 22 番はインターネットに出さない。
resource "google_compute_firewall" "allow_iap" {
  name    = "${var.name_prefix}-allow-iap"
  network = google_compute_network.staging.id

  allow {
    protocol = "tcp"
    # 22   SSH（トンネル・ポートフォワード）
    # 80   DevStack の Horizon / OpenStack API、platform の Caddy
    # 443  Caddy (TLS)
    # 8080 Harbor
    # 9000 Authentik（Caddy を通さず直接見たいとき用）
    ports = ["22", "80", "443", "8080", "9000"]
  }

  source_ranges = [local.iap_range]
  target_tags   = [local.tag]
}

# platform VM の各サービスから DevStack の Keystone / Nova / Neutron へ直接届かせる。
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.name_prefix}-allow-internal"
  network = google_compute_network.staging.id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = [local.tag]
}

# --- 公開 ---

# Caddy（TLS 終端）だけをインターネットに出す。
# 80 番も開けるのは Let's Encrypt の HTTP-01 チャレンジに要るため。
# Caddy は 80 に来た通常の要求を 443 へリダイレクトする。
resource "google_compute_firewall" "allow_public_https" {
  count   = local.publish ? 1 : 0
  name    = "${var.name_prefix}-allow-public-https"
  network = google_compute_network.staging.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.name_prefix}-public"]
}

# DevStack は送信元 CIDR を絞って平文 HTTP で出す。
# TLS を挟まないので、許可する範囲は信頼できる回線に限ること（variables.tf の注記）。
resource "google_compute_firewall" "allow_devstack_ranges" {
  count   = length(var.devstack_allowed_source_ranges) > 0 ? 1 : 0
  name    = "${var.name_prefix}-allow-devstack-ranges"
  network = google_compute_network.staging.id

  allow {
    protocol = "tcp"
    # 80    Horizon / OpenStack API（Apache 前段）
    # 6080  noVNC コンソール
    ports = ["80", "6080"]
  }

  source_ranges = var.devstack_allowed_source_ranges
  target_tags   = ["${var.name_prefix}-devstack"]
}

resource "google_compute_firewall" "allow_harbor_ranges" {
  count   = length(var.harbor_allowed_source_ranges) > 0 ? 1 : 0
  name    = "${var.name_prefix}-allow-harbor-ranges"
  network = google_compute_network.staging.id

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = var.harbor_allowed_source_ranges
  target_tags   = ["${var.name_prefix}-public"]
}

resource "google_project_iam_member" "iap_tunnel_accessor" {
  for_each = toset(var.iap_tunnel_users)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

# --- IP アドレス ---

# 内部 IP は固定する。DevStack は HOST_IP を各サービスの設定ファイルと
# Keystone のサービスカタログに焼き込むため、変わると
# 「一見動いているが一部が古い IP を向いている」状態になる。
resource "google_compute_address" "devstack_internal" {
  name         = "${var.name_prefix}-devstack-internal"
  subnetwork   = google_compute_subnetwork.staging.id
  address_type = "INTERNAL"
  address      = var.devstack_internal_ip
  region       = var.region
}

resource "google_compute_address" "platform_internal" {
  name         = "${var.name_prefix}-platform-internal"
  subnetwork   = google_compute_subnetwork.staging.id
  address_type = "INTERNAL"
  address      = var.platform_internal_ip
  region       = var.region
}

# 外部 IP は静的に取る。DNS の A レコードを向ける先になるため、
# VM の停止・起動で変わっては困る。
#
# 静的 IP は VM を止めている間も課金される（asia-northeast1 で月 1,745 円/個）。
# 公開しない構成（dns_zone も allowed_source_ranges も空）ならエフェメラルで
# 足りるので、その場合は静的 IP を作らない。
locals {
  devstack_needs_static_ip = local.publish || length(var.devstack_allowed_source_ranges) > 0
  platform_needs_static_ip = local.publish || length(var.harbor_allowed_source_ranges) > 0
}

resource "google_compute_address" "devstack_external" {
  count  = local.devstack_needs_static_ip ? 1 : 0
  name   = "${var.name_prefix}-devstack-external"
  region = var.region
}

resource "google_compute_address" "platform_external" {
  count  = local.platform_needs_static_ip ? 1 : 0
  name   = "${var.name_prefix}-platform-external"
  region = var.region
}
