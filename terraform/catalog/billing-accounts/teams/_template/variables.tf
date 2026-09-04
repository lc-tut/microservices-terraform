variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（admin 権限）"
  default     = "polaris-admin"
}

variable "team_name" {
  type        = string
  description = "catalog/teams/<team_name>/ に対応する名前（project 名として lookup する）"
}

variable "quota_tier" {
  type    = string
  default = "lc-small"

  validation {
    condition = contains([
      "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "チーム請求アカウントは lc-small 以上を指定してください（07-quota.md 参照）。"
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
