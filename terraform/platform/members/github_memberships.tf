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
