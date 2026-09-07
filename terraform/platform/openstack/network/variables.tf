variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（admin 権限。外部ネットワークに触るため）。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "external_network_name" {
  type        = string
  description = "int-router の外部ゲートウェイに使う既存の外部ネットワーク名（Polaris チームが用意したもの。ネットワーク自体の作成・変更はしない）"
  default     = "ext-net"
}

variable "external_subnet_cidr" {
  type        = string
  description = "ext-net にぶら下げる外部サブネット（ext-subnet）の CIDR"
  default     = "160.187.27.0/24"
}

variable "external_subnet_gateway" {
  type        = string
  description = "ext-subnet のデフォルトゲートウェイ（上位ネットワーク側のルーター）"
  default     = "160.187.27.1"
}

variable "external_subnet_pool_start" {
  type        = string
  description = "ext-subnet の allocation pool 開始アドレス。Floating IP と router の外部固定 IP はここから払い出される"
  default     = "160.187.27.10"
}

variable "external_subnet_pool_end" {
  type        = string
  description = "ext-subnet の allocation pool 終了アドレス"
  default     = "160.187.27.200"
}

variable "internal_subnet_cidr" {
  type        = string
  description = "共有内部サブネット（int-subnet）の CIDR。platform 自身の VM と個人プロジェクトの VM が乗る。クラスタ内部用 172.16.192.0/18 の前半"
  default     = "172.16.192.0/19"
}

variable "subnetpool_prefix" {
  type        = string
  description = "チームプロジェクト専用 subnet 払い出し用マスタープールの CIDR。クラスタ内部用 172.16.192.0/18 の後半。int-subnet とは重ねないこと"
  default     = "172.16.224.0/19"
}

variable "project_subnet_prefixlen" {
  type        = number
  description = "catalog/projects/ が subnetpool から払い出す1プロジェクトあたりのサブネット長（/26 固定。VM は 61 台まで）"
  default     = 26
}

variable "dns_nameservers" {
  type        = list(string)
  description = "ext-subnet・int-subnet に設定する DNS サーバー"
  default     = ["1.1.1.1"]
}
