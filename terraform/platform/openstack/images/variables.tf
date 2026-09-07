variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント。image の作成には admin か image 作成権限を持つプロジェクトの認証情報が必要。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "ubuntu_image_name" {
  type        = string
  description = "Glance に登録するイメージ名。catalog/projects/・workspaces/ 側からはこの名前で参照する"
  default     = "ubuntu-24.04"
}

variable "ubuntu_image_source_url" {
  type        = string
  description = "Ubuntu 24.04(Noble) 公式 cloud image の qcow2 URL。バージョン更新時はここを変える"
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ubuntu_min_disk_gb" {
  type    = number
  default = 10
}

variable "ubuntu_min_ram_mb" {
  type    = number
  default = 1024
}

variable "rocky_image_name" {
  type        = string
  description = "Rocky Linux 10 ベースイメージの Glance 登録名（infra/* の VM が data 参照する）"
  default     = "rocky-10"
}

variable "rocky_image_source_url" {
  type        = string
  description = "Rocky 10 GenericCloud qcow2 の web_download 元 URL"
  default     = "https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud.latest.x86_64.qcow2"
}

variable "rocky_min_disk_gb" {
  type    = number
  default = 10
}

variable "rocky_min_ram_mb" {
  type    = number
  default = 1024
}
