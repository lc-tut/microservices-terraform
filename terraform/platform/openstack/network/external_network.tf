# 外部ネットワーク（ext-net）は OpenStack 管理者が用意した既存インフラであり、
# platform/network/ で作成・変更はしない（data 参照のみ）。
data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

# ext-net 自体の shared 属性は false（実機確認済み・2026-09-04）。全プロジェクトから
# 外部ゲートウェイとして使えているのは、この RBAC ポリシー
# （action=access_as_external, target_tenant=*）が既に存在するため。
# 「ネットワーク共有ポリシー」（12-openstack-resources.md）として platform/network/
# が管理する対象そのものなので、新規作成ではなく import して管理下に置く。
#   terraform import openstack_networking_rbac_policy_v2.ext_net_external <policy_id>
# project_id は computed（作成時の認証スコープで自動決定・変更不可）のため
# 指定できない。apply する cloud のプロジェクトが所有者になる。
resource "openstack_networking_rbac_policy_v2" "ext_net_external" {
  action        = "access_as_external"
  object_type   = "network"
  object_id     = data.openstack_networking_network_v2.external.id
  target_tenant = "*"
}
