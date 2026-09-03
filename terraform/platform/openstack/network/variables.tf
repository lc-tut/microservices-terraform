variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名。lc-dev プロジェクトにスコープされていること（idp-infra と同じ理由で admin パスワード認証を使う）"
  default     = "polaris-admin"
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
