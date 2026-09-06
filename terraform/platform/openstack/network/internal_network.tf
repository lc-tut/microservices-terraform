# 共有内部ネットワーク。platform 自身の VM（Authentik・Harbor 等）と個人
# プロジェクトの VM がここに乗る。チームプロジェクトは catalog/projects/ が
# subnetpool から /24 を取って専用ネットワークを作り、同じ int-router に繋ぐ。
# 外向き通信は経路を問わず int-router に集約する（project 個別の NAT・
# 独自 LB・interface_attach は禁止。12-openstack-resources.md）。
resource "openstack_networking_network_v2" "internal" {
  name           = "internal-net"
  admin_state_up = true
}

# gateway_ip は指定しない。Neutron が CIDR の先頭（172.16.192.1）を割り当てる。
resource "openstack_networking_subnet_v2" "internal" {
  name       = "int-subnet"
  network_id = openstack_networking_network_v2.internal.id
  ip_version = 4

  cidr            = var.internal_subnet_cidr
  dns_nameservers = var.dns_nameservers
}

# internal-net は admin プロジェクトの所有物なので、個人プロジェクトが port を
# 作れるよう共有ポリシーを張る。internal-net は共有 L2 一枚でネットワーク自体には
# テナント境界が無く、そこに乗る VM の分離は Security Group が担う。
resource "openstack_networking_rbac_policy_v2" "internal_shared" {
  action        = "access_as_shared"
  object_type   = "network"
  object_id     = openstack_networking_network_v2.internal.id
  target_tenant = "*"
}

resource "openstack_networking_router_v2" "internal" {
  name           = "int-router"
  admin_state_up = true
  enable_snat    = true

  external_network_id = data.openstack_networking_network_v2.external.id

  # 外部側の固定 IP を ext-subnet から取ることを明示する
  # （ext-net にサブネットが増えても払い出し元がぶれない）。
  external_fixed_ip {
    subnet_id = openstack_networking_subnet_v2.external.id
  }
}

resource "openstack_networking_router_interface_v2" "internal" {
  router_id = openstack_networking_router_v2.internal.id
  subnet_id = openstack_networking_subnet_v2.internal.id
}
