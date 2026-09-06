# ext-net 自体は OpenStack 管理者が用意した既存インフラなので data 参照のみ。
data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

# 外部アドレス帯。Floating IP と int-router の外部ゲートウェイをここから払い出す。
# 外部ネットワークなので DHCP は無効。allocation pool 外のアドレスは
# 物理機材・手動割り当て用に空けてある。
resource "openstack_networking_subnet_v2" "external" {
  name       = "ext-subnet"
  network_id = data.openstack_networking_network_v2.external.id
  ip_version = 4

  cidr        = var.external_subnet_cidr
  gateway_ip  = var.external_subnet_gateway
  enable_dhcp = false

  allocation_pool {
    start = var.external_subnet_pool_start
    end   = var.external_subnet_pool_end
  }

  dns_nameservers = var.dns_nameservers
}

# ext-net の shared 属性は false のため、全プロジェクトから外部ゲートウェイとして
# 使えるようにこのポリシーを張る。project_id は computed（apply する cloud の
# プロジェクトが所有者になる）。
resource "openstack_networking_rbac_policy_v2" "ext_net_external" {
  action        = "access_as_external"
  object_type   = "network"
  object_id     = data.openstack_networking_network_v2.external.id
  target_tenant = "*"
}
