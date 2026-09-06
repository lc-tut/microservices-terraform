variable "github_token" {
  type      = string
  sensitive = true
}

variable "github_org" {
  type    = string
  default = "lc-tut"
}

variable "authentik_url" {
  type    = string
  default = "http://localhost:9000"
}

variable "authentik_token" {
  type      = string
  sensitive = true
}

variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（admin 権限）。個人 project の作成に使う"
  default     = "polaris-admin"
}
