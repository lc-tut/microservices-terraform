# VPC Gateway router。全 project subnet の外向き通信をここに集約する。
# project 個別の NAT・独自 LB・interface_attach は禁止
# （openstack_compute_interface_attach_v2 は BLOCKED。12-openstack-resources.md）。
# router interface（project subnet の接続）は catalog/projects/ 側の責務で、
# ここでは router 本体のみを作成する。
#
# 実機確認済み（2026-09-04）: 新規作成ではなく、既に存在する router
# "lc-dev-router"（lc-dev-net ⇔ ext-net、SNAT 有効）を import して管理下に
# 置く方針にした。新規に別ルーターを作ると重複するため。
#   terraform import openstack_networking_router_v2.vpc_gateway <router_id>
# name・admin_state_up・enable_snat・external_network_id は import 元の実際の
# 値に合わせてある（apply しても diff が出ない状態を確認済み）。
resource "openstack_networking_router_v2" "vpc_gateway" {
  name           = "lc-dev-router"
  admin_state_up = true
  enable_snat    = true

  external_network_id = data.openstack_networking_network_v2.external.id
}
