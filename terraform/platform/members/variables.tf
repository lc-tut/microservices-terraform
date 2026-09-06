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
