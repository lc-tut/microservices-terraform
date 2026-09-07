output "vm" {
  description = "VM / port / SG / IP。API の稼働完了を意味しない。"
  value = {
    id                = openstack_compute_instance_v2.vm["infra"].id
    name              = openstack_compute_instance_v2.vm["infra"].name
    port_id           = openstack_networking_port_v2.vm["infra"].id
    security_group_id = openstack_networking_secgroup_v2.vm["infra"].id
    private_ip        = one(openstack_networking_port_v2.vm["infra"].all_fixed_ips)
    floating_ip       = try(openstack_networking_floatingip_v2.vm["infra"].address, null)
  }
}
