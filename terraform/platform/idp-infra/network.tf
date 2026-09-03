resource "openstack_networking_secgroup_v2" "authentik" {
  name        = "authentik-idp"
  description = "Authentik IdP VM: SSH + Authentik UI/API (9000/9443) + ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.authentik.id
  description       = "SSH"
}

resource "openstack_networking_secgroup_rule_v2" "authentik_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9000
  port_range_max    = 9000
  remote_ip_prefix  = var.ui_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.authentik.id
  description       = "Authentik UI/API (HTTP)"
}

resource "openstack_networking_secgroup_rule_v2" "authentik_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9443
  port_range_max    = 9443
  remote_ip_prefix  = var.ui_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.authentik.id
  description       = "Authentik UI/API (HTTPS)"
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.authentik.id
  description       = "ping (疎通確認用)"
}

# Nova 生成ポートの ID は openstack_compute_instance_v2.network[].port として
# 安定して読めない（OVN 構成では null になる）ため、ポートを明示的に作成し
# SG と Floating IP をこのポートに紐づける。
resource "openstack_networking_port_v2" "authentik" {
  name                  = "authentik-idp"
  network_id            = data.openstack_networking_network_v2.private.id
  admin_state_up        = true
  security_group_ids    = [openstack_networking_secgroup_v2.authentik.id]
  no_security_groups    = false
  port_security_enabled = true

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private.id
  }
}

resource "openstack_networking_floatingip_v2" "authentik" {
  pool        = data.openstack_networking_network_v2.external.name
  description = "Authentik IdP"
}

resource "openstack_networking_floatingip_associate_v2" "authentik" {
  floating_ip = openstack_networking_floatingip_v2.authentik.address
  port_id     = openstack_networking_port_v2.authentik.id
}
