# IP 帯域マスタープール。catalog/projects/ がここから /24 単位でプロジェクト
# サブネットを払い出す（05-project-lifecycle.md・12-openstack-resources.md）。
# shared = true で他プロジェクトからも subnetpool_id を参照して subnet を
# 作成できるようにする（サブネット自体の所有者はそれぞれの project になる）。
#
# 実機適用済み（2026-09-04）。既存の lc-dev-subnet（10.10.0.0/24、この pool とは
# 無関係に手動作成・subnetpool_id=null）とは重ならない: Neutron の自動払い出しは
# 10.0.0.0/24 から順に採番するため 10.10.0.0/24 に到達するまで 2560 個の /24 を
# 消費する必要があり、現実的な規模では衝突しない。到達しても Neutron 側が
# router へのインターフェース接続時に CIDR 重複を検知して拒否する。
resource "openstack_networking_subnetpool_v2" "platform" {
  name        = "lc-cloud-pool"
  description = "LC-Cloud project subnet 払い出し用マスタープール"

  prefixes = [var.subnetpool_prefix]

  default_prefixlen = var.project_subnet_prefixlen
  min_prefixlen     = var.project_subnet_prefixlen
  max_prefixlen     = var.project_subnet_prefixlen

  shared = true
}
