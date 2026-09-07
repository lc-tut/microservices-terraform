variable "os_auth_url" {
  type        = string
  default     = null
  description = "Keystone の認証エンドポイント。null なら OS_AUTH_URL 環境変数から解決する"
}

variable "external_network_name" {
  type        = string
  default     = "public"
  description = <<-EOT
    外部ネットワークの名前。DevStack は "public" で作る（本番は "ext-net"）。
    catalog/projects/ が張る router の外部ゲートウェイ先になる。
  EOT
}

variable "router_name" {
  type        = string
  default     = "lc-vpc-gateway"
  description = "仮の VPC Gateway ルーター名"
}

variable "subnetpool_name" {
  type        = string
  default     = "lc-subnetpool"
  description = "仮の IP 帯域マスタープール名"
}

variable "subnetpool_prefixes" {
  type        = list(string)
  default     = ["10.100.0.0/16"]
  description = <<-EOT
    プロジェクトのサブネットを切り出す元の帯域。
    DevStack 既定の private(10.0.0.0/26 前後)・trove-mgmt(192.168.254.0/24)・
    br-ex(172.24.4.0/24) と重ならない範囲にしている。
  EOT
}

variable "subnetpool_default_prefixlen" {
  type        = number
  default     = 24
  description = "プロジェクトごとに切り出すサブネットの大きさ"
}
