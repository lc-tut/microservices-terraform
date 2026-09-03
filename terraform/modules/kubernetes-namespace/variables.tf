variable "name" {
  type = string
}

variable "quota_tier" {
  type    = string
  default = "lc-small"

  validation {
    condition = contains([
      "lc-micro", "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "有効なティア名を指定してください。"
  }
}

variable "k8s_quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します。"
  type = object({
    requests_cpu    = optional(string)
    limits_cpu      = optional(string)
    requests_memory = optional(string)
    limits_memory   = optional(string)
    pods            = optional(number)
    services        = optional(number)
    pvcs            = optional(number)
    storage         = optional(string)
  })
  default = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "allow_from_namespaces" {
  type        = list(string)
  description = "この Namespace へのアクセスを許可する追加 Namespace 名（例: monitoring）"
  default     = []
}

variable "ingress_controller_namespace" {
  type    = string
  default = "rke2-ingress-nginx"
}
