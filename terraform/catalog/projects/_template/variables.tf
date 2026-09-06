variable "project_name" {
  type        = string
  description = "プロジェクト名。ネットワーク・Application Credential の名前に使う"
}

variable "team_project_id" {
  type        = string
  description = "所属チームの OpenStack project ID。catalog/teams/<team-name>/ の terraform output -raw openstack_project_id を渡す"
}

variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（admin 権限。network/subnet/router_interface の作成に使う）。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "subnetpool_id" {
  type        = string
  description = "terraform/platform/openstack/network/ の terraform output -raw subnetpool_id"
}

variable "vpc_gateway_router_id" {
  type        = string
  description = "terraform/platform/openstack/network/ の terraform output -raw vpc_gateway_router_id"
}
