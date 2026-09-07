# チームプロジェクト専用 subnet を払い出すマスタープール。catalog/projects/ が
# ここから /26 を1つずつ取る。CIDR を人間が選ぶと採番ミスで衝突するため、
# 空きブロックの選択は Neutron に任せる。
#
# shared = true で他プロジェクトからも subnetpool_id を参照して subnet を
# 作成できるようにする（subnet 自体の所有者はそれぞれの project になる）。
#
# アドレスはラボ側が「クラスタ内部用」として確保した 172.16.192.0/18 の中だけで
# 完結させ、その外は取りに行かない。
#   172.16.192.0/19  int-subnet（共有内部ネットワーク）
#   172.16.224.0/19  このプール（/26 × 128 チームプロジェクト）
# 172.16.100.0/24 は SAN network（MTU 9000）なので触れない。10.x はラボ側が
# 10.200.192.0/19 を使っている。172.17.0.0/16 以降は Docker の既定アドレスプールで、
# VM の中の bridge と衝突する。
resource "openstack_networking_subnetpool_v2" "platform" {
  name        = "lc-cloud-pool"
  description = "LC-Cloud プロジェクト subnet 払い出し用マスタープール"

  prefixes = [var.subnetpool_prefix]

  default_prefixlen = var.project_subnet_prefixlen
  min_prefixlen     = var.project_subnet_prefixlen
  max_prefixlen     = var.project_subnet_prefixlen

  shared = true
}
