variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（cloudkitty-infra と同じプロジェクトにスコープされていること）"
  default     = "polaris-admin"
}

variable "instance_name" {
  type    = string
  default = "prometheus"
}

variable "image_name" {
  type    = string
  default = "rocky-10"
}

variable "flavor_name" {
  type        = string
  description = "Prometheus + openstack-exporter を動かす最小現実解"
  default     = "m1.small"
}

variable "root_volume_size" {
  type        = number
  description = "ルートボリューム GB。Prometheus TSDB の保持期間分の余裕を見て 20"
  default     = 20
}

variable "private_network_name" {
  type    = string
  default = "lc-dev-net"
}

variable "external_network_name" {
  type    = string
  default = "ext-net"
}

variable "ssh_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "prometheus_allowed_cidr" {
  type        = string
  description = "Prometheus(9090) を許可する送信元 CIDR。cloudkitty-infra 等 PromQL クライアントからの apply 元を許可する"
  default     = "0.0.0.0/0"
}

variable "prometheus_image" {
  type    = string
  default = "docker.io/prom/prometheus:v3.1.0"
}

variable "prometheus_retention" {
  type        = string
  description = "TSDB retention（Prometheus の --storage.tsdb.retention.time）"
  default     = "45d"
}

variable "openstack_exporter_image" {
  type        = string
  description = "openstack-exporter イメージ。2.0.0-alpha は cinder(limits_volume_used_gb) / neutron floating_ip を出す。1.7.0(最新stable)・1.8.0-alpha は cinder 無し・flavor_id が <nil> なので不可"
  default     = "ghcr.io/openstack-exporter/openstack-exporter:2.0.0-alpha"
}

variable "openstack_exporter_scrape_interval" {
  type    = string
  default = "60s"
}

# ---- exporter が読み取る OpenStack 環境 ----
variable "keystone_auth_url" {
  type        = string
  description = "openstack-exporter が使う Keystone の auth_url（例: http://<host>:5000/v3）"
}

variable "os_admin_username" {
  type    = string
  default = "admin"
}

variable "os_admin_password" {
  type        = string
  description = "上記ユーザーのパスワード。cloudkitty-infra と同じ資格情報を使う想定"
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
