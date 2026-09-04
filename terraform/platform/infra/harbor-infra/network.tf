resource "openstack_networking_secgroup_v2" "harbor" {
  name        = "harbor-infra"
  description = "Harbor VM: SSH + HTTP(80) + ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.harbor.id
  description       = "SSH"
}

resource "openstack_networking_secgroup_rule_v2" "harbor_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.harbor_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.harbor.id
  description       = "Harbor portal/registry (HTTP)"
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.harbor.id
  description       = "ping (疎通確認用)"
}

# Nova 生成ポートの ID は openstack_compute_instance_v2.network[].port として
# 安定して読めない（OVN 構成では null になる）ため、ポートを明示的に作成し
# SG と Floating IP をこのポートに紐づける（idp-infra/network.tf と同じ方針）。
resource "openstack_networking_port_v2" "harbor" {
  name                  = "harbor-infra"
  network_id            = data.openstack_networking_network_v2.private.id
  admin_state_up        = true
  security_group_ids    = [openstack_networking_secgroup_v2.harbor.id]
  no_security_groups    = false
  port_security_enabled = true

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private.id
  }
}

resource "openstack_networking_floatingip_v2" "harbor" {
  pool        = data.openstack_networking_network_v2.external.name
  description = "Harbor"
}

resource "openstack_networking_floatingip_associate_v2" "harbor" {
  floating_ip = openstack_networking_floatingip_v2.harbor.address
  port_id     = openstack_networking_port_v2.harbor.id
}
