variable "team_name" {
  type        = string
  description = "チーム名。Authentik Group 名・OpenStack project 名の両方に使う"
}

variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（project 作成のため admin 権限が必要）。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "authentik_url" {
  type    = string
  default = "http://localhost:9000"
}

variable "authentik_token" {
  type      = string
  sensitive = true
}

variable "subnetpool_id" {
  type        = string
  description = "terraform/platform/openstack/network/ の terraform output -raw subnetpool_id。ここから /26 を払い出す"
}

variable "router_id" {
  type        = string
  description = "terraform/platform/openstack/network/ の terraform output -raw internal_router_id（int-router）"
}

variable "subnet_block_count" {
  type        = number
  description = "チームネットワークに張る /26 の本数。61 台を超えたら増やす（既存 VM は無停止）"
  default     = 1

  validation {
    condition     = var.subnet_block_count >= 1
    error_message = "1 以上を指定してください。"
  }
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
