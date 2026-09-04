variable "team_name" {
  type        = string
  description = "チーム名。Authentik Group 名・OpenStack project 名の両方に使う"
}

variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（admin 権限が必要）"
  default     = "polaris-admin"
}

variable "authentik_url" {
  type    = string
  default = "http://localhost:9000"
}

variable "authentik_token" {
  type      = string
  sensitive = true
}

variable "automation_username" {
  type        = string
  description = "CI が Application Credential 発行等に使う Keystone ユーザー名。このプロジェクトに member ロールを付与する（lc_cloud.tf 参照）"
  default     = "admin"
}

variable "quota_tier" {
  type        = string
  description = "07-quota.md 参照。チームのデフォルトは lc-small"
  default     = "lc-small"

  validation {
    condition = contains([
      "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "チームは lc-small 以上を指定してください（07-quota.md 参照）。"
  }
}

variable "quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します（modules/lc-cloud-quota 参照）。"
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
