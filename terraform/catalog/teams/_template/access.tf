# チーム内の権限管理（documents/terraform/18-access-control.md）。
#
# このファイルが作るのは「グループ」と「グループへの権限付与」だけで、
# 「誰がそのグループに入るか」は作らない。ユーザーのグループ所属は
# terraform/platform/members/ が唯一の書き込み口になる（理由は下の
# 「所属の書き込み口について」参照）。

module "roles" {
  source     = "../../../modules/lc-role-map"
  scope_type = "team"
  scope_name = var.team_name
}

locals {
  # 宣言ファイル。owners.yaml と members.yaml が分かれているのは
  # 「権限を配る権限」を CODEOWNERS のファイル単位の粒度で守るため
  owners_decl  = try(yamldecode(file("${path.module}/owners.yaml")).owners, [])
  members_decl = try(yamldecode(file("${path.module}/members.yaml")).members, [])
  team_policy  = yamldecode(file("${path.module}/team.yaml")).policy

  # ロール => [lcn_id...]。owner は owners.yaml、それ以外は members.yaml から引く
  members_by_role = {
    owner  = [for o in local.owners_decl : o.id]
    member = [for m in local.members_decl : m.id if m.role == "member"]
    viewer = [for m in local.members_decl : m.id if m.role == "viewer"]
  }

  all_declared_ids = concat(
    local.members_by_role.owner,
    [for m in local.members_decl : m.id],
  )

  declared_grants = flatten([for m in local.members_decl : try(m.grants, [])])

  # ---- メンバー台帳との突き合わせ ----
  # platform/members/<status>/grad-XXXX/members.yaml を直接読む。
  # state ではなくファイルを読むのは、この repo の既存方針
  # （値は remote state ではなく明示的に橋渡しする）と揃えるため。
  # 「卒業した人の権限が消えずに残る」のを plan 時点で構造的に防ぐのが目的。
  ledger_dir   = "${path.module}/../../../platform/members"
  ledger_files = fileset(local.ledger_dir, "*/*/members.yaml")

  _ledger_maps = [
    for f in local.ledger_files : {
      for m in try(yamldecode(file("${local.ledger_dir}/${f}")).members, []) :
      m.id => split("/", f)[0] # active / ob-og / alumni
    }
  ]
  ledger_status = length(local._ledger_maps) > 0 ? merge(local._ledger_maps...) : {}

  unknown_ids  = [for id in local.all_declared_ids : id if !contains(keys(local.ledger_status), id)]
  inactive_ids = [for id in local.all_declared_ids : id if try(local.ledger_status[id], "active") != "active"]
  invalid_grants = [
    for g in local.declared_grants : g if !contains(module.roles.grants, g)
  ]
  invalid_roles = [
    for m in local.members_decl : m.role if !contains(["member", "viewer"], m.role)
  ]
}

# 不変条件の検証。CI スクリプトではなく Terraform の precondition で弾くことで、
# plan の時点で（＝ PR のレビューが始まる前に）失敗させる。
# 台帳との突き合わせ以外の項目もここにまとめてある。
resource "terraform_data" "access_invariants" {
  input = {
    owners  = local.members_by_role.owner
    members = local.members_by_role.member
    viewers = local.members_by_role.viewer
  }

  lifecycle {
    precondition {
      condition     = length(local.members_by_role.owner) >= 2
      error_message = <<-EOT
        owners.yaml には owner を 2 人以上登録してください（現在 ${length(local.members_by_role.owner)} 人）。
        GitHub は PR 作成者自身の CODEOWNERS 承認をカウントしないため、
        owner が 1 人だとそのチームの PR を誰もマージできなくなります。
      EOT
    }

    precondition {
      condition     = length(local.all_declared_ids) == length(distinct(local.all_declared_ids))
      error_message = "owners.yaml と members.yaml で同じ id が重複しています。1 人につき 1 ロールだけ宣言してください。"
    }

    precondition {
      condition     = length(local.invalid_roles) == 0
      error_message = <<-EOT
        members.yaml の role には member または viewer のみ指定できます（不正な値: ${join(", ", local.invalid_roles)}）。
        owner は owners.yaml 側で宣言してください（circle-admin の承認が必要です）。
      EOT
    }

    precondition {
      condition     = length(local.invalid_grants) == 0
      error_message = <<-EOT
        未定義の grant が指定されています: ${join(", ", local.invalid_grants)}
        使用できる語彙: ${join(", ", module.roles.grants)}
        語彙の追加は modules/lc-role-map への PR（circle-admin 承認）で行ってください。
      EOT
    }

    precondition {
      condition     = length(local.unknown_ids) == 0
      error_message = <<-EOT
        メンバー台帳（terraform/platform/members/）に存在しない id です: ${join(", ", local.unknown_ids)}
        先に platform/members/ へ登録してください。
      EOT
    }

    precondition {
      condition     = length(local.inactive_ids) == 0
      error_message = <<-EOT
        active でないメンバーが残っています: ${join(", ", local.inactive_ids)}
        ob-og / alumni になったメンバーは owners.yaml / members.yaml から削除してください。
      EOT
    }
  }
}

# ---- Authentik: ロールごとのグループ ----
# 権限の主体（subject）はこのグループ。個人に直接権限を張ることはしない。
resource "authentik_group" "role" {
  for_each = toset(module.roles.roles)

  name         = module.roles.group_names[each.key]
  is_superuser = false

  attributes = jsonencode({
    lc_scope_type = "team"
    lc_scope_name = var.team_name
    lc_role       = each.key
  })

  # users は設定しない（＝ Optional + Computed なのでサーバー側の値を維持する）。
  # 所属は platform/members/ が authentik_user.groups 側から一元的に書く。
  # 両側から書くと Authentik の API はどちらも「集合の置き換え」なので、
  # 2 つのスタックが互いの変更を消し合う無限 drift になる。
}

# ---- Keystone: ロールごとのグループ + プロジェクトへのロール付与 ----
# OIDC フェデレーションで入ってくるユーザーは Keystone にローカル実体を持たないため、
# ロールは必ずグループに張り、federation mapping が Authentik のグループクレームを
# 同名の Keystone グループへ写す（[P2]・04-idp.md 参照）。
resource "openstack_identity_group_v3" "role" {
  for_each = toset(module.roles.roles)

  name        = module.roles.group_names[each.key]
  description = "LC-Cloud team ${var.team_name}: ${each.key}"
}

# 写像先の Keystone ロールを名前で解決する。
# owner と member はどちらも "member" に写るため、実際に引くのは member / reader の 2 つ。
data "openstack_identity_role_v3" "role_by_name" {
  for_each = toset(values(module.roles.keystone_role))
  name     = each.key
}

resource "openstack_identity_role_assignment_v3" "team" {
  for_each = openstack_identity_group_v3.role

  project_id = openstack_identity_project_v3.this.id
  group_id   = each.value.id
  role_id    = data.openstack_identity_role_v3.role_by_name[module.roles.keystone_role[each.key]].id
}
