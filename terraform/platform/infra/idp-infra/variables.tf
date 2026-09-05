variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（lc-dev プロジェクトにスコープされていること）"
  default     = "polaris-admin"
}

variable "instance_name" {
  type    = string
  default = "authentik"
}

variable "image_name" {
  type        = string
  description = "ベース OS イメージ名（Polaris に登録済みのもの）"
  default     = "rocky-10"
}

variable "flavor_name" {
  type        = string
  description = "Authentik(server+worker+postgres) を Docker Compose で動かす最小現実解。m1.small(2GB) は逼迫するため m1.medium(4GB/2vCPU/40GB) を既定にする"
  default     = "m1.medium"
}

variable "root_volume_size" {
  type        = number
  description = "ルートボリューム GB。docker イメージ(~2GB) + postgres データ + ログを見込んで 20（実機の lc-dev 規模なら十分な余裕）"
  default     = 20
}

variable "private_network_name" {
  type    = string
  default = "lc-dev-net"
}

variable "external_network_name" {
  type        = string
  description = "Floating IP を払い出す外部ネットワーク"
  default     = "ext-net"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "SSH(22) を許可する送信元 CIDR。Polaris は閉じたラボnetwork(192.168.1.0/24 経由)のため既定は全開放"
  default     = "0.0.0.0/0"
}

variable "ui_allowed_cidr" {
  type        = string
  description = "Authentik UI/API(9000,9443) を許可する送信元 CIDR"
  default     = "0.0.0.0/0"
}

variable "authentik_image" {
  type        = string
  description = "Authentik コンテナイメージ。local/authentik/docker-compose.yml と揃える"
  default     = "ghcr.io/goauthentik/server:2026.5.6"
}

variable "postgres_image" {
  type    = string
  default = "docker.io/library/postgres:16-alpine"
}

# ---- SMTP（recovery / annual renewal メール送信用のグローバル設定） ----
# 空文字なら Authentik はメール設定なしで起動する（terraform/platform/idp/ 側は
# smtp_host 未設定時 use_global_settings=true にフォールバックするため、
# ここで設定しておくと idp/ apply 時に TF_VAR_smtp_* を毎回渡さなくて済む）。
variable "authentik_email_host" {
  type    = string
  default = ""
}

variable "authentik_email_port" {
  type    = number
  default = 587
}

variable "authentik_email_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "authentik_email_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "authentik_email_use_tls" {
  type    = bool
  default = true
}

variable "authentik_email_use_ssl" {
  type    = bool
  default = false
}

variable "authentik_email_from" {
  type    = string
  default = ""
}
