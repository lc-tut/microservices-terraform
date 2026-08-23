variable "authentik_url" {
  type    = string
  default = "http://localhost:9000"
}

variable "authentik_token" {
  type      = string
  sensitive = true
}

# GitHub OAuth Source（任意連携）— 空文字のままにすると Source は作成されない
variable "github_oauth_client_id" {
  type    = string
  default = ""
}

variable "github_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# LC-Cloud OIDC プロバイダ — 空文字のままにするとプロバイダは作成されない
variable "lc_cloud_oidc_client_id" {
  type    = string
  default = ""
}

variable "lc_cloud_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# enrollment 完了 / GitHub 連携変更 の Webhook HMAC シークレット
# 空文字のままにすると通知 Transport は作成されない
variable "webhook_secret" {
  type      = string
  sensitive = true
  default   = ""
  description = "GitHub Actions repository_dispatch の HMAC シークレット"
}

variable "github_repo_owner" {
  type    = string
  default = "lc-tut"
}

variable "github_repo_name" {
  type    = string
  default = "microservices-terraform"
}

# ---- SMTP（enrollment / recovery メール送信） ----
# TF_VAR_smtp_host が空の場合は use_global_settings = true にフォールバックする
variable "smtp_host" {
  type        = string
  description = "SMTPサーバーホスト名。空文字の場合はAuthentikのDockerコンテナ環境変数を使用する"
  default     = ""
}

variable "smtp_port" {
  type        = number
  description = "SMTPポート番号（587=STARTTLS, 465=SSL）"
  default     = 587
}

variable "smtp_username" {
  type        = string
  description = "SMTP認証ユーザー名"
  default     = ""
}

variable "smtp_password" {
  type        = string
  description = "SMTP認証パスワード"
  sensitive   = true
  default     = ""
}

variable "smtp_use_tls" {
  type        = bool
  description = "STARTTLSを使用するか（ポート587推奨）"
  default     = false
}

variable "smtp_use_ssl" {
  type        = bool
  description = "Implicit SSLを使用するか（ポート465/2465推奨）"
  default     = false
}

variable "smtp_from_address" {
  type        = string
  description = "メール送信元アドレス"
  default     = ""
}
