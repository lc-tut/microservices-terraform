variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（admin 権限。外部ネットワークに触るため）。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "external_network_name" {
  type        = string
  description = "access_as_external RBAC を管理する対象の外部ネットワーク名（手動で用意済み）"
  default     = "ext-net"
}
