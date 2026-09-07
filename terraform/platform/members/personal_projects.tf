# 個人 OpenStack project。台帳の active メンバー全員に 1 つずつ作る。
#
# catalog/ ではなく platform/members/ に置くのは、個人 project が
# 「台帳の関数」だからです。catalog/users/<id>/ のようなディレクトリを
# 人ごとに作る方式にすると、グループを data source で参照することになり、
# 「新しいディレクトリを先に apply してから members/ を apply する」という
# 2 段階 apply が入会のたびに必要になります。入会は最も頻度の高い運用なので、
# ここで完結させます。
#
# クォータを既定から変えたい人だけが catalog/billing-accounts/personal/<lcn_id>/
# を作ります（そちらは data source で project を引くだけ）。
#
# 既定は最小構成です。ネットワークはそもそもプロジェクトごとに作らず、
# 全員が platform/openstack/network/ の共有 internal-net を使います。
# Application Credential も作りません（1 つあたり約 40 本の access rule を
# 持つため、人数分作ると数千本になる）。必要になったら申請して足します。
#
# 個人 project の VM は Neutron の default SG（同一 project 内からの ingress
# のみ許可）に守られます。共有 internal-net 上でも他人の project からは
# 届きません。詳細は platform/openstack/network/README.md を参照。

locals {
  # active のみ。ob-og / alumni になったら project ごと消える。
  # 「台帳の status を変えるだけで権限が確実に外れる」という
  # 既存の性質（18-access-control.md）を、個人 project にもそのまま効かせる。
  personal_project_members = {
    for id, m in local.members_by_id : id => m if m.status == "active"
  }

  # scope_name はアンダースコアを許さないため lcn_xxx → lcn-xxx に正規化する。
  # username を使わないのは、本人が enrollment 後に変更でき、
  # Terraform も ignore_changes で追随しないため（authentik_users.tf 参照）。
  personal_scope_names = {
    for id, _ in local.personal_project_members : id => replace(id, "_", "-")
  }
}

module "personal_roles" {
  source   = "../../modules/lc-role-map"
  for_each = local.personal_project_members

  scope_type = "user"
  scope_name = local.personal_scope_names[each.key]
}

resource "openstack_identity_project_v3" "personal" {
  for_each = local.personal_project_members

  # team-<name> と名前空間を分ける。接頭辞が無いとチーム名と衝突しうる。
  name        = "user-${local.personal_scope_names[each.key]}"
  domain_id   = "default"
  description = "LC-Cloud personal project: ${each.key}"
  enabled     = true
}

# Neutron は quota-class-set に相当する API を持たず、
# platform/openstack/quotas/ も Nova と Cinder しか設定していない。
# ここでクォータを明示しないと Neutron 側だけ OpenStack 素の既定
# （floatingip 50 等）になり、人数分で外部 IP プールを食い潰す。
# 個人 project では必ず適用すること。
module "personal_quota" {
  source   = "../../modules/lc-cloud-quota"
  for_each = local.personal_project_members

  project_id = openstack_identity_project_v3.personal[each.key].id
  tier       = "lc-micro"
}

# ---- Authentik: 本人だけが入るグループ ----
# OIDC フェデレーションで入ってくるユーザーは Keystone にローカル実体を
# 持たないため、ロールはグループにしか張れません。1 人グループは妥協ではなく
# 唯一の実装手段です（18-access-control.md「この写像が『漏れる』ところ」）。
#
# ロールは owner だけです。roles を回すと空の -member / -viewer が残るため、
# scope_roles を使います。
resource "authentik_group" "personal_owner" {
  for_each = local.personal_project_members

  name         = module.personal_roles[each.key].group_names["owner"]
  is_superuser = false

  attributes = jsonencode({
    lc_scope_type = "user"
    lc_scope_name = local.personal_scope_names[each.key]
    lc_role       = "owner"
  })

  # users は設定しない。所属は authentik_users.tf の groups 側から一元的に書く
  # （両側から書くと集合の置き換え同士で無限 drift になる）。
}

# ---- Keystone: 同名グループ + project へのロール付与 ----
resource "openstack_identity_group_v3" "personal_owner" {
  for_each = local.personal_project_members

  name        = module.personal_roles[each.key].group_names["owner"]
  description = "LC-Cloud personal project ${each.key}: owner"
}

# owner は Keystone 上 member ロールに写る（lc-role-map の写像表）。
data "openstack_identity_role_v3" "personal_role" {
  name = "member"
}

resource "openstack_identity_role_assignment_v3" "personal_owner" {
  for_each = local.personal_project_members

  project_id = openstack_identity_project_v3.personal[each.key].id
  group_id   = openstack_identity_group_v3.personal_owner[each.key].id
  role_id    = data.openstack_identity_role_v3.personal_role.id
}
