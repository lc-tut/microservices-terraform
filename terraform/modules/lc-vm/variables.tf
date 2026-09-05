variable "name" {
  type        = string
  description = "VM名。同一プロジェクト内で一意にすること"
}

variable "project_name" {
  type        = string
  description = "所属する catalog/projects の名前。同名の network/subnet を data source で自動解決する"
}

variable "flavor" {
  type        = string
  description = "Nova flavor名（例: m1.medium。将来 platform/ が lc-micro 等の専用flavorを定義したらそちらに移行予定）"
}

variable "image" {
  type        = string
  description = "Glance イメージ名（例: ubuntu-24.04-lts）。most_recent=true で解決する"
}

variable "volume_size_gb" {
  type        = number
  default     = 20
  description = "ルートボリューム(boot-from-volume)のサイズ(GB)"
}

variable "volume_type" {
  type        = string
  default     = null
  description = "Cinder volume type。null ならバックエンドのデフォルトを使う"
}

variable "ssh_ca_public_key" {
  type        = string
  description = <<-EOT
    sshd の TrustedUserCAKeys に設定する CA 公開鍵(OpenSSH形式)。
    platform/openstack/images の output `ssh_ca_public_key_openssh` を渡す想定。
    鍵ペア(openstack_compute_keypair_v2)は使わない方針のため必須。
  EOT
}

variable "user_data" {
  type        = string
  default     = ""
  description = "アプリ固有の追加 cloud-init(YAML cloud-config または shebang スクリプト)。CA trust設定と多重パートで合成される"
}

variable "allow_ssh_from_project_subnet" {
  type        = bool
  default     = true
  description = "プロジェクトの subnet CIDR から SSH(22)・ICMP を許可するデフォルトルールを追加するか"
}

variable "security_group_rules" {
  type = list(object({
    direction        = string # "ingress" | "egress"
    ethertype        = optional(string, "IPv4")
    protocol         = optional(string) # null で全プロトコル
    port_range_min   = optional(number)
    port_range_max   = optional(number)
    remote_ip_prefix = optional(string)
  }))
  default     = []
  description = "追加のセキュリティグループルール。allow_ssh_from_project_subnet でカバーされない通信はここで定義する"
}

variable "metadata" {
  type        = map(string)
  default     = {}
  description = "インスタンスの metadata"
}
