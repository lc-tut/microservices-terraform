resource "authentik_group" "this" {
  name         = var.team_name
  is_superuser = false
}
