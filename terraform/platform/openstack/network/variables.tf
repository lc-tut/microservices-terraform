variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（admin 権限。外部ネットワークに触るため）。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "external_network_name" {
  type        = string
  description = "VPC Gateway router の外部ゲートウェイに使う既存の外部ネットワーク名（Polaris チームが用意したもの。作成・変更はしない）"
  default     = "ext-net"
}

variable "subnetpool_prefix" {
  type        = string
  description = "project subnet 払い出し用マスタープールの CIDR（05-project-lifecycle.md の設計通り 10.0.0.0/8）"
  default     = "10.0.0.0/8"
}

variable "project_subnet_prefixlen" {
  type        = number
  description = "catalog/projects/ が subnetpool から払い出す1プロジェクトあたりのサブネット長（/24 固定。12-openstack-resources.md 参照）"
  default     = 24
}
