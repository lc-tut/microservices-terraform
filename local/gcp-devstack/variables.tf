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
  description = "VM マシンタイプ（DevStack + Harbor 同居のため最低でも 16GB メモリを推奨）"
  type        = string
  default     = "e2-standard-4"
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
