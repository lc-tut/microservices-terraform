# enrollment 完了 かつ GitHub 連携済みのメンバーを GitHub Org に追加する
resource "github_membership" "this" {
  for_each = {
    for id, m in local.members_by_id : id => m
    if(
      lookup(local.auto_gen, id, null) != null &&
      lookup(local.github_usernames, id, null) != null
    )
  }

  username = local.github_usernames[each.key]
  role     = each.value.role == "circle-admin" ? "admin" : "member"
}

# ob-og/alumni チームは terraform/platform/github/ 側の別スタックが所有するため data source で参照
data "github_team" "ob_og" {
  slug = "ob-og"
}

data "github_team" "alumni" {
  slug = "alumni"
}

resource "github_team_membership" "ob_og" {
  for_each = {
    for id, m in local.members_by_id : id => m
    if m.status == "ob-og" && lookup(local.github_usernames, id, null) != null
  }

  team_id  = data.github_team.ob_og.id
  username = local.github_usernames[each.key]
}

resource "github_team_membership" "alumni" {
  for_each = {
    for id, m in local.members_by_id : id => m
    if m.status == "alumni" && lookup(local.github_usernames, id, null) != null
  }

  team_id  = data.github_team.alumni.id
  username = local.github_usernames[each.key]
}
