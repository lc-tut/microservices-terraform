# チームのロール別グループへの所属を、メンバー台帳側から一元的に書く。
#
# ## 所属の書き込み口を 1 つにする理由
#
# Authentik は authentik_user.groups と authentik_group.users のどちらからでも
# 所属を書けるが、API はどちらも「集合の丸ごと置き換え」である。
# そのため catalog/teams/ が group.users を書き、ここが user.groups を書くと、
# 2 つのスタックが apply のたびに互いの変更を消し合う無限 drift になる。
#
# よって役割を分ける:
#   catalog/teams/<t>/access.tf … グループを作り、グループに権限を張る
#   ここ（platform/members/）  … 誰がどのグループに入るかを書く
#
# 宣言そのものは catalog/teams/<t>/{owners,members}.yaml にあり、
# 承認ゲートは CODEOWNERS がそのファイルに対して掛ける。
# apply するスタックが Tier 1 でも、変更を承認できる人は変わらない。
#
# ## apply 順序
#
# ここは data source でグループを名前解決するため、
# **新チームは catalog/teams/<t>/ を先に apply しておく必要がある**。
# 新チーム作成とメンバー追加は別 PR に分けるか、CI で catalog/teams/ →
# platform/members/ の順に apply すること。

locals {
  teams_dir = "${path.module}/../../catalog/teams"

  team_names = sort([
    for f in fileset(local.teams_dir, "*/team.yaml") : dirname(f)
    if dirname(f) != "_template"
  ])

  team_owner_ids = {
    for t in local.team_names : t => [
      for o in try(yamldecode(file("${local.teams_dir}/${t}/owners.yaml")).owners, []) : o.id
    ]
  }

  team_member_decl = {
    for t in local.team_names : t => try(
      yamldecode(file("${local.teams_dir}/${t}/members.yaml")).members, []
    )
  }

  # (team, role, id) の平坦なリスト
  team_role_assignments = flatten([
    for t in local.team_names : concat(
      [for id in local.team_owner_ids[t] : { team = t, role = "owner", id = id }],
      [for m in local.team_member_decl[t] : { team = t, role = m.role, id = m.id }],
    )
  ])

  assigned_member_ids = distinct([for a in local.team_role_assignments : a.id])
  team_role_pairs     = distinct([for a in local.team_role_assignments : "${a.team}/${a.role}"])

  # lcn_id => 所属する Authentik グループ ID（チーム包括グループ + ロール別グループ）
  team_groups_by_member = {
    for id in local.assigned_member_ids : id => distinct(concat(
      [
        for a in local.team_role_assignments :
        data.authentik_group.team_umbrella[a.team].id if a.id == id
      ],
      [
        for a in local.team_role_assignments :
        data.authentik_group.team_role["${a.team}/${a.role}"].id if a.id == id
      ],
    ))
  }

  # lcn_id => アドオン権限。Middleware API が OIDC クレーム経由で読む想定
  # （実際の消費は 18-access-control.md の実装ステップ 4 以降）
  grants_by_member = {
    for id in local.assigned_member_ids : id => sort(distinct(flatten([
      for t in local.team_names : [
        for m in local.team_member_decl[t] : try(m.grants, []) if m.id == id
      ]
    ])))
  }
}

# グループ名の組み立て規則は modules/lc-role-map にしか無い。
# ここで "team-${t}-${role}" と直接書くと写像表が 2 箇所に増えてしまう
module "team_roles" {
  source   = "../../modules/lc-role-map"
  for_each = toset(local.team_names)

  scope_type = "team"
  scope_name = each.key
}

# グループの実体は catalog/teams/<t>/ が所有するため data source で参照する
data "authentik_group" "team_umbrella" {
  for_each = toset(local.team_names)
  name     = each.key
}

data "authentik_group" "team_role" {
  for_each = toset(local.team_role_pairs)

  name = module.team_roles[
    split("/", each.key)[0]
  ].group_names[split("/", each.key)[1]]
}
