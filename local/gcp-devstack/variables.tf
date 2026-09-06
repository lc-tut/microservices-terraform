variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "リソースを作成するリージョン"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "VM を作成するゾーン"
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "VM インスタンス名"
  type        = string
  default     = "devstack-harbor"
}

variable "machine_type" {
  description = <<-EOT
    VM マシンタイプ（DevStack + Harbor 同居のため最低でも 16GB メモリを推奨）。
    E2 系はネステッド仮想化に非対応で /dev/kvm が使えないため、
    Trove のような重いゲストイメージを起動する検証ができない。
    そのため N2 系を既定にしている（enable_nested_virtualization も参照）。
  EOT
  type        = string
  default     = "n2-standard-4"
}

variable "enable_nested_virtualization" {
  description = <<-EOT
    ネステッド仮想化。DevStack の Nova が建てる VM を KVM で動かすために必要。
    false にすると Nova は virt_type=qemu になり、cirros 程度の軽いゲスト
    （lc-vm の検証）は動くが、Trove のゲストイメージ（Ubuntu + Docker で
    約 1.4GB）は起動しきらず ERROR になる。
    有効にできるのは N1/N2/N2D/C2 等のみで、E2 では apply が失敗する。
  EOT
  type        = bool
  default     = true
}

variable "boot_disk_image" {
  description = "ブートディスクイメージ"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_size_gb" {
  description = "ブートディスクサイズ（DevStack + Harbor のイメージ/コンテナ領域を含む）"
  type        = number
  default     = 100
}

variable "harbor_version" {
  description = "インストールする Harbor のバージョン（オンラインインストーラのタグ）。 https://github.com/goharbor/harbor/releases で最新の安定版を確認して更新すること"
  type        = string
  default     = "v2.15.2"
}

variable "devstack_admin_password" {
  description = "DevStack の admin / service パスワード（Keystone admin, DB, RabbitMQ 共通で使用）"
  type        = string
  sensitive   = true
}

variable "harbor_admin_password" {
  description = "Harbor admin ユーザーのパスワード"
  type        = string
  sensitive   = true
}

variable "iap_tunnel_users" {
  description = "IAP トンネル (roles/iap.tunnelResourceAccessor) を許可するユーザー一覧（\"user:you@example.com\" 形式）"
  type        = list(string)
  default     = []
}
