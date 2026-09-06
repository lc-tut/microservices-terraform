variable "project_name" {
  type        = string
  description = "プロジェクト名。Security Group・Application Credential の名前に使う"
}

variable "team_project_id" {
  type        = string
  description = "所属チームの OpenStack project ID。catalog/teams/<team-name>/ の terraform output -raw openstack_project_id を渡す"
}

variable "os_auth_url" {
  type        = string
  description = "Keystone の認証エンドポイント（admin 権限。チームネットワークの参照と team_scoped provider の元認証に使う）。null なら OS_AUTH_URL 環境変数から解決する（ローカルは OS_CLOUD + clouds.yaml も可）"
  default     = null
}

variable "team_network_name" {
  type        = string
  description = "所属チームの catalog/teams/<team-name>/ の terraform output -raw network_name（チーム専用ネットワーク）"
}
