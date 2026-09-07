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

# admin は運用者のプロジェクトであり、クォータで守る相手が居ない（クォータは
# テナントを互いから守るための仕組み）。ここを有限値にすると、実機の空き容量
# ではなく我々が書いた数字が先に上限になる。実際 lc-standard-32 相当
# （cores 32）を入れてみたところ、下記の実容量に対して明らかに小さかった。
# よって -1（無制限）にし、実効上限をハードウェアそのものに委ねる。
#
# 実機容量（2026-09-07、Nova os-hypervisors/detail・Cinder scheduler-stats）:
#   compute : lc-sv01 / lc-sv02 / lc-sv03 の 3 台
#             合計 168 vCPU・673800 MB (658 GB)・local 8046 GB（使用量 0）
#   cinder  : ceph@rbd-1  total 808 GB / free 808 GB
#
# つまり Cinder は元の gigabytes=800 でほぼプール全量に達していた。詰まって
# いたのは Nova 側（cores 2 → 32 → 無制限）。
resource "openstack_compute_quotaset_v2" "admin" {
  project_id = data.openstack_identity_project_v3.admin.id

  instances = -1
  cores     = -1
  ram       = -1

  server_groups        = -1
  server_group_members = -1
  key_pairs            = -1
  metadata_items       = -1
}

resource "openstack_blockstorage_quotaset_v3" "admin" {
  project_id = data.openstack_identity_project_v3.admin.id

  volumes              = -1
  snapshots            = -1
  gigabytes            = -1
  per_volume_gigabytes = -1
  backups              = -1
  backup_gigabytes     = -1
}
