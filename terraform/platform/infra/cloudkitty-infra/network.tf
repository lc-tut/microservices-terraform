# 実機確認（2026-09-04）: 既存 VM を import して継続するため、name/description
# は既存の値（手動構築時に付けたもの）に合わせてある。
resource "openstack_networking_secgroup_v2" "cloudkitty" {
  name        = "cloudkitty-sg"
  description = "cloudkitty-sg"
}

# description は既存ルールに合わせて空のまま（description は force-new 属性のため
# 実機確認済みの値と食い違うとルールが destroy → create されてしまう。2026-09-04）。
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.cloudkitty.id
}

resource "openstack_networking_secgroup_rule_v2" "cloudkitty_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8889
  port_range_max    = 8889
  remote_ip_prefix  = var.api_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.cloudkitty.id
}

resource "openstack_networking_secgroup_rule_v2" "gnocchi_legacy" {
  # 実機確認（2026-09-04）: 既存 SG に手動で開けられていたポート。8041 は
  # Gnocchi API の既定ポートで、当時 Gnocchi collector を試した名残と思われる
  # （現構成は prometheus collector で Gnocchi は使っていない）。実害は無いため
  # 既存に合わせてそのまま残す。将来使わないと確認できたら削除してよい。
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8041
  port_range_max    = 8041
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cloudkitty.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cloudkitty.id
}

# Nova 生成ポートの ID は openstack_compute_instance_v2.network[].port として
# 安定して読めない（OVN 構成では null になる）ため、ポートを明示的に作成し
# SG と Floating IP をこのポートに紐づける（idp-infra/network.tf と同じ方針）。
resource "openstack_networking_port_v2" "cloudkitty" {
  name                  = "cloudkitty-infra"
  network_id            = data.openstack_networking_network_v2.private.id
  admin_state_up        = true
  security_group_ids    = [openstack_networking_secgroup_v2.cloudkitty.id]
  no_security_groups    = false
  port_security_enabled = true

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private.id
  }
}

resource "openstack_networking_floatingip_v2" "cloudkitty" {
  pool        = data.openstack_networking_network_v2.external.name
  description = "CloudKitty"
}

resource "openstack_networking_floatingip_associate_v2" "cloudkitty" {
  floating_ip = openstack_networking_floatingip_v2.cloudkitty.address
  port_id     = openstack_networking_port_v2.cloudkitty.id
}
