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
}

# 外から入れるのは IAP トンネル経由だけ。インターネットには一切公開しない。
resource "google_compute_firewall" "allow_iap" {
  name    = "${var.name_prefix}-allow-iap"
  network = google_compute_network.staging.id

  allow {
    protocol = "tcp"
    # 22   SSH（IAP トンネル本体・SOCKS5 プロキシ）
    # 80   DevStack の Horizon / OpenStack API、platform の ingress-nginx
    # 443  ingress-nginx (TLS)
    # 8080 Harbor
    # 9000 Authentik
    ports = ["22", "80", "443", "8080", "9000"]
  }

  source_ranges = [local.iap_range]
  target_tags   = [local.tag]
}

# platform VM の k3s から DevStack の Keystone / Nova / Neutron へ直接届かせる。
# DevStack のサービスカタログは HOST_IP（内部 IP）を返すので、同じ VPC にいる
# platform VM は SOCKS5 プロキシ無しでそのまま使える。手元から使うときだけ
# プロキシが要る（start-tunnels.sh 参照）。
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

resource "google_project_iam_member" "iap_tunnel_accessor" {
  for_each = toset(var.iap_tunnel_users)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

# 内部 IP のみ予約する。外部 IP は静的に取らずエフェメラルのままにしている:
#   - 到達経路は IAP トンネルだけなので外部 IP を固定する意味がない
#   - 静的 IP は VM を止めている間も課金される（asia-northeast1 で月 1,745 円/個）。
#     エフェメラルなら VM 停止と同時に解放され、止めている間は 0 円になる
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
