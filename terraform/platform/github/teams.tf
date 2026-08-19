resource "github_team" "circle_admin" {
  name        = "circle-admin"
  description = "役員（部長・副部長・幹部）。全 Tier 承認・組織最終決定権"
  privacy     = "closed"
}

resource "github_team" "tech_lead" {
  name        = "tech-lead"
  description = "技術全般のリーダー。platform/ 全体の技術的オーナー"
  privacy     = "closed"
}

resource "github_team" "lc_cloud_infra" {
  name        = "lc-cloud-infra"
  description = "OpenStack・Ceph・K8s 担当。インフラ層・クォータ・IdP 管理"
  privacy     = "closed"
}

resource "github_team" "lc_cloud_platform" {
  name        = "lc-cloud-platform"
  description = "Terraform・Authentik・GitHub 担当。プラットフォーム・モジュール・CI/CD 管理"
  privacy     = "closed"
}

resource "github_team" "all_leads" {
  name        = "all-leads"
  description = "全チームリードの集合（Tier 3 デフォルト承認者）"
  privacy     = "closed"
}
