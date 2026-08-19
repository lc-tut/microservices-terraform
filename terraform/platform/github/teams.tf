resource "github_team" "circle_admin" {
  name        = "circle-admin"
  description = "Executive members (president, vice-president, officers)"
  privacy     = "closed"
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
