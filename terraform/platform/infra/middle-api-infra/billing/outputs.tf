output "vm" {
  description = "VM / port / SG / IP。API の稼働完了を意味しない。"
  value = {
    id                = openstack_compute_instance_v2.vm["billing"].id
    name              = openstack_compute_instance_v2.vm["billing"].name
    port_id           = openstack_networking_port_v2.vm["billing"].id
    security_group_id = openstack_networking_secgroup_v2.vm["billing"].id
    private_ip        = one(openstack_networking_port_v2.vm["billing"].all_fixed_ips)
    floating_ip       = try(openstack_networking_floatingip_v2.vm["billing"].address, null)
  }
}
