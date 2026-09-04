variable "project_name" {
  type        = string
  description = "プロジェクト名。ネットワーク・Application Credential の名前に使う"
}

variable "team_project_id" {
  type        = string
  description = "所属チームの OpenStack project ID。catalog/teams/<team-name>/ の terraform output -raw openstack_project_id を渡す"
}

variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（admin 権限。network/subnet/router_interface の作成に使う）"
  default     = "polaris-admin"
}

variable "subnetpool_id" {
  type        = string
  description = "terraform/platform/openstack/network/ の terraform output -raw subnetpool_id"
}

variable "vpc_gateway_router_id" {
  type        = string
  description = "terraform/platform/openstack/network/ の terraform output -raw vpc_gateway_router_id"
}
