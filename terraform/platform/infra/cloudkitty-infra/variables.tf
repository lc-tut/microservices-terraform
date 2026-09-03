variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（idp-infra と同じプロジェクトにスコープされていること）"
  default     = "polaris-admin"
}

variable "instance_name" {
  type    = string
  default = "cloudkitty"
}

variable "image_name" {
  type        = string
  description = "ベース OS イメージ名（環境に登録済みのもの）"
  default     = "rocky-10"
}

variable "flavor_name" {
  type        = string
  description = "CloudKitty(api+processor) + MariaDB + InfluxDB を Docker Compose で動かす最小現実解"
  default     = "m1.medium"
}

variable "root_volume_size" {
  type        = number
  description = "ルートボリューム GB。InfluxDB のメトリクス蓄積分の余裕を見て 30"
  default     = 30
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
  description = "SSH(22) を許可する送信元 CIDR"
  default     = "0.0.0.0/0"
}

variable "api_allowed_cidr" {
  type        = string
  description = "CloudKitty API(8889) を許可する送信元 CIDR。terraform/platform/openstack/cloudkitty/ からの apply 元を許可する"
  default     = "0.0.0.0/0"
}

variable "ck_image_tag" {
  type        = string
  description = "cloudkitty-api / cloudkitty-processor イメージタグ（Kolla イメージ）"
  default     = "2026.1-rocky-10"
}

variable "mariadb_image" {
  type    = string
  default = "docker.io/library/mariadb:11.4"
}

variable "influxdb_image" {
  type    = string
  default = "docker.io/library/influxdb:1.8"
}

# ---- Keystone（keystone_authtoken / fetcher_keystone 用） ----
# CloudKitty 自身は Keystone を経由してトークン検証・プロジェクト一覧取得を行う。
# ここで指すのは「CloudKitty を動かす OpenStack 環境の Keystone」であり、環境ごとに
# 異なる（本番では apply 時に -var 等で明示的に渡す。既定値は置かない）。
variable "keystone_auth_url" {
  type        = string
  description = "CloudKitty が受信トークンの検証・プロジェクト一覧取得に使う Keystone の auth_url（例: http://<host>:5000）"
}

variable "os_admin_username" {
  type        = string
  description = "keystone_authtoken / fetcher_keystone 用の OpenStack 管理者ユーザー名"
  default     = "admin"
}

variable "os_admin_password" {
  type        = string
  description = "上記ユーザーのパスワード。ローテーション対象。将来はサービスユーザー + application credential に置き換える想定（infra/cloudkitty-infra/README.md 参照）"
  sensitive   = true
}

variable "os_admin_project_name" {
  type    = string
  default = "admin"
}

variable "os_region_name" {
  type    = string
  default = "RegionOne"
}

# ---- Prometheus（別インスタンス。infra/prometheus-infra/ が構築） ----
variable "prometheus_url" {
  type        = string
  description = "CloudKitty の collector_prometheus.prometheus_url に設定する値（例: http://<prometheus-infra の Floating IP>:9090/api/v1）。infra/prometheus-infra/ の terraform output から取得する"
}
