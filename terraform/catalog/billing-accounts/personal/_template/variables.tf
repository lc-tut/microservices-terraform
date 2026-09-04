variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（admin 権限）"
  default     = "polaris-admin"
}

variable "username" {
  type        = string
  description = "個人 OpenStack project 名（プロジェクト作成の運用規約: 1人1project、project名=username を前提とする。ただし個人project自動作成自体は未実装、README参照）"
}

variable "quota_tier" {
  type    = string
  default = "lc-micro"

  validation {
    condition = contains([
      "lc-micro", "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "有効なティア名を指定してください（07-quota.md 参照）。"
  }
}

variable "quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します。"
  type = object({
    instances            = optional(number)
    cores                = optional(number)
    ram_gb               = optional(number)
    volumes              = optional(number)
    snapshots            = optional(number)
    gigabytes            = optional(number)
    per_volume_gigabytes = optional(number)
    backups              = optional(number)
    backup_gigabytes     = optional(number)
    network              = optional(number)
    subnet               = optional(number)
    port                 = optional(number)
    router               = optional(number)
    floatingip           = optional(number)
    security_group       = optional(number)
    security_group_rule  = optional(number)
  })
  default = {}
}
