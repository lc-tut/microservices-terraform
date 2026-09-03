resource "openstack_networking_secgroup_v2" "prometheus" {
  name        = "prometheus-infra"
  description = "Prometheus VM: SSH + Prometheus (9090) + ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.prometheus.id
  description       = "SSH"
}

resource "openstack_networking_secgroup_rule_v2" "prometheus_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9090
  port_range_max    = 9090
  remote_ip_prefix  = var.prometheus_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.prometheus.id
  description       = "Prometheus HTTP API/UI"
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.prometheus.id
  description       = "ping (疎通確認用)"
}

resource "openstack_networking_port_v2" "prometheus" {
  name                  = "prometheus-infra"
  network_id            = data.openstack_networking_network_v2.private.id
  admin_state_up        = true
  security_group_ids    = [openstack_networking_secgroup_v2.prometheus.id]
  no_security_groups    = false
  port_security_enabled = true

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private.id
  }
}

resource "openstack_networking_floatingip_v2" "prometheus" {
  pool        = data.openstack_networking_network_v2.external.name
  description = "Prometheus"
}

resource "openstack_networking_floatingip_associate_v2" "prometheus" {
  floating_ip = openstack_networking_floatingip_v2.prometheus.address
  port_id     = openstack_networking_port_v2.prometheus.id
}
