# 本番の「VPC Gateway ルーター」と「IP 帯域マスタープール」に相当する**仮の**もの。
#
# 本番ではこの2つは OpenStack 管理者が手で用意した既存インフラで、
# terraform/platform/openstack/network/ からはコードごと外されている
# （コミット 644bd74）。catalog/projects/_template/ は ID を変数
# （vpc_gateway_router_id / subnetpool_id）で受け取るだけになっている。
#
# staging には用意してくれる管理者がいないので、ここで作る。**本番と同じ形を
# 再現するのが目的ではなく、catalog/projects/ が動くのに必要な受け皿を置くだけ。**
# だから帯域も名前もこのファイルの中で完結していて、本番の値とは揃えていない。
#
# 使い方:
#   staging/terraform/tf.sh staging/openstack apply
#   terraform -chdir=staging/openstack output

# DevStack が作る外部ネットワーク。本番の ext-net に相当する。
# **これ自体は作らない。** 外部ネットワークは OpenStack の基盤側が用意するもので、
# 本番でも platform/openstack/network/ は data 参照しかしていない
data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

# プロジェクトのサブネットを切り出す元。
# catalog/projects/_template/lc_cloud.tf の openstack_networking_subnet_v2 が
# subnetpool_id で参照し、CIDR を指定せずに切り出す
resource "openstack_networking_subnetpool_v2" "lc" {
  name              = var.subnetpool_name
  prefixes          = var.subnetpool_prefixes
  default_prefixlen = var.subnetpool_default_prefixlen
  min_prefixlen     = var.subnetpool_default_prefixlen
  ip_version        = 4
  shared            = true
}

# 全プロジェクトのサブネットがぶら下がる1本のルーター。
# catalog/projects/_template が openstack_networking_router_interface_v2 で
# ここに subnet を足していく。
#
# 本番と同じく**1本に集約する**。人数分の router を作らないのは、
# 外向き通信がここに集まる設計だから（platform/members/personal_projects.tf の
# コメント参照）。staging でも同じ形にしておかないと、詰まり方の再現ができない
resource "openstack_networking_router_v2" "vpc_gateway" {
  name                = var.router_name
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}
