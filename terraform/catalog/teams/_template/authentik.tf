# チーム全員が入る包括グループ。ロールに関係なく「このチームの人」を指す。
# 通知の宛先やチーム単位の識別に使う用途で、権限そのものは持たせない。
# 実際の権限は access.tf のロール別グループ（team-<name>-owner/member/viewer）に張る。
resource "authentik_group" "this" {
  name         = var.team_name
  is_superuser = false
}
