variable "github_token" {
  type      = string
  sensitive = true
}

variable "github_org" {
  type    = string
  default = "lc-tut"
}

variable "authentik_url" {
  type    = string
  default = "http://localhost:9000"
}

variable "authentik_token" {
  type      = string
  sensitive = true
}

variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（admin 権限）。個人 project の作成に使う。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "send_enrollment_email" {
  type        = bool
  default     = true
  description = <<-EOT
    新規 active メンバーにウェルカムメールを送るか。

    **staging では false にすること。** 台帳（members_secrets.yaml）には本物の
    メールアドレスが入っているので、検証環境から apply すると本物の招待メールが
    本人に届く。staging の Authentik は本番と同じメールサーバーを使う設定なので、
    「検証環境だから届かない」という保護は無い。
  EOT
}
