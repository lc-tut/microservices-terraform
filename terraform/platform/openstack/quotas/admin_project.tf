# 管理者プロジェクト（platform/infra/ の VM 群を載せる先）を、このルートが設定する
# グローバルデフォルト（= lc-micro 相当）から明示的に除外する。
#
# admin project は Terraform 管理外（Kolla のデプロイ時に作られる既存
# プロジェクト）なので resource ではなく data で引く。
#
# Nova / Cinder の quota class "default" は「プロジェクト個別の quota 行を持たない
# 全プロジェクト」への fallback であり、admin も例外ではない。実機で確認した
# 状態（2026-09-07、Keystone/Nova/Cinder API 直叩き）:
#
#   projects           : admin, service の 2 つだけ
#   admin の nova quota: cores 2 / instances 3 / ram 4096  (in_use は全て 0)
#   admin の cinder    : volumes 5 / gigabytes 50          (in_use は全て 0)
#
# つまり main.tf の nova_default / cinder_default をそのまま食っている。
# platform/infra/ の 4 VM（idp / harbor / cloudkitty = m1.medium、
# prometheus = m1.small。合計 7 vCPU・14336 MB・4 volume・80 GB）はまだ
# 立っていないが、この枠のままでは最初の apply が "Quota exceeded" で落ちる。
#
# 現在の使用量が 0 なので、枠を広げる方向のこの変更は既存リソースに影響しない。
#
# Neutron はここでは触らない。このルートは元々 Neutron を管理対象外にしており
# （README.md「実装方式」参照）、admin の Neutron クォータは OpenStack 素の既定
# （floatingip 50 等）のまま十分に大きい。modules/lc-cloud-quota のティアを
# 当てると floatingip 5〜10 まで逆に絞られるため、Nova と Cinder だけを明示する。

data "openstack_identity_project_v3" "admin" {
  name = var.admin_project_name
}

# 値は platform/infra/ の想定使用量（7 vCPU / 14 GB / 4 instance / 80 GB）に対し、
# 全 VM の同時再構築でも詰まらない程度の余裕を見た。lc-standard-32 相当。
resource "openstack_compute_quotaset_v2" "admin" {
  project_id = data.openstack_identity_project_v3.admin.id

  instances = 20
  cores     = 32
  ram       = 65536

  server_groups        = 20
  server_group_members = 5
  key_pairs            = 20
  metadata_items       = 128
}

resource "openstack_blockstorage_quotaset_v3" "admin" {
  project_id = data.openstack_identity_project_v3.admin.id

  volumes              = 40
  snapshots            = 40
  gigabytes            = 800
  per_volume_gigabytes = 800
  backups              = 20
  backup_gigabytes     = 800
}
