resource "github_team" "circle_admin" {
  name        = "circle-admin"
  description = "Executive members (president, vice-president, officers)"
  privacy     = "closed"
}

# 実機確認済み（2026-09-04）: branch_protection.tf の restrict_pushes は
# circle-admin チームを push_allowances に加えているが、GitHub はそのチームが
# 対象リポジトリへの何らかのアクセス権を持っていないと push_allowances への
# 追加を（エラーも出さず）無視する。この関連付けが無かったため、
# terraform apply が毎回「成功」と表示されるのに実際には反映されない
# 状態が続いていた
resource "github_team_repository" "circle_admin" {
  team_id    = github_team.circle_admin.id
  repository = var.github_repo
  permission = "admin"
}

resource "github_team" "tech_lead" {
  name        = "tech-lead"
  description = "Technical leads"
  privacy     = "closed"
}

resource "github_team" "lc_cloud_infra" {
  name        = "lc-cloud-infra"
  description = "Infrastructure (OpenStack, K8s)"
  privacy     = "closed"
}

resource "github_team" "lc_cloud_platform" {
  name        = "lc-cloud-platform"
  description = "Platform (Terraform, Authentik, GitHub)"
  privacy     = "closed"
}

resource "github_team" "all_leads" {
  name        = "all-leads"
  description = "All project leads"
  privacy     = "closed"
}

# チームメンバーは Org member である必要があるため ob-og/alumni も Org からは削除しない。
# repository 権限は一切紐づけないことでアクセスを絞る
resource "github_team" "ob_og" {
  name        = "ob-og"
  description = "卒業後もサークルに関わる OB/OG（repository 権限なし）"
  privacy     = "closed"
}

resource "github_team" "alumni" {
  name        = "alumni"
  description = "退会済みメンバー（記録用。repository 権限なし）"
  privacy     = "closed"
}
