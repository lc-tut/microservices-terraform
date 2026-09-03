variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名。admin 権限（image の作成には admin か image の作成権限を持つプロジェクトが必要）"
  default     = "polaris-admin"
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
