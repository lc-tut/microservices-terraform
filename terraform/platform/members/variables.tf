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
