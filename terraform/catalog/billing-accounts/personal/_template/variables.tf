variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（admin 権限）"
  default     = "polaris-admin"
}

variable "lcn_id" {
  type        = string
  description = <<-EOT
    メンバーの不変識別子（platform/members/ の台帳のキー。例 lcn_9a2bb6e30171）。
    username ではなく lcn_id を使うのは、username は本人が enrollment 後に
    変更でき、Terraform も ignore_changes で追随しないため。username を
    キーにすると、改名した時点で project 名と実体がずれる。
  EOT

  validation {
    condition     = can(regex("^lcn_[0-9a-f]{12}$", var.lcn_id))
    error_message = "lcn_id は lcn_ + 12桁の小文字16進で指定してください（例 lcn_9a2bb6e30171）。"
  }
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
