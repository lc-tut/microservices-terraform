# ローカル開発用 DevStack + Harbor を GCP 上に構築する
# terraform/ 配下の本番 IaC とは独立（state はローカル管理、S3 backend は使わない）

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- ネットワーク（他プロジェクトと分離した専用 VPC） ---

resource "google_compute_network" "devstack" {
  name                    = "devstack-harbor"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "devstack" {
  name          = "devstack-harbor"
  network       = google_compute_network.devstack.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/24"
}

# IAP (Identity-Aware Proxy) の TCP フォワーディング元レンジ。
# https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule
locals {
  iap_range = "35.235.240.0/20"
}

resource "google_compute_firewall" "allow_iap" {
  name    = "devstack-harbor-allow-iap"
  network = google_compute_network.devstack.id

  # SSH(22) / Horizon・OpenStack API(80) / Harbor(8080)
  # いずれも世界には公開せず、IAP トンネル経由のみ許可する
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "8080"]
  }

  source_ranges = [local.iap_range]
  target_tags   = ["devstack-harbor"]
}

resource "google_project_iam_member" "iap_tunnel_accessor" {
  for_each = toset(var.iap_tunnel_users)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

# --- 静的外部 IP（VM の起動/停止を繰り返しても IP を固定するため） ---

resource "google_compute_address" "devstack" {
  name   = "devstack-harbor"
  region = var.region
}

# --- VM 本体 ---

resource "google_compute_instance" "devstack" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["devstack-harbor"]

  # 自動停止スクリプトから start/stop を繰り返す運用のため、
  # マシンタイプ変更等でも VM 自体は保持できるようにしておく
  allow_stopping_for_update = true

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
      nat_ip = google_compute_address.devstack.address
    }
  }

  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    devstack_admin_password = var.devstack_admin_password
    harbor_admin_password   = var.harbor_admin_password
    external_ip             = google_compute_address.devstack.address
    harbor_version          = var.harbor_version
  })
}
