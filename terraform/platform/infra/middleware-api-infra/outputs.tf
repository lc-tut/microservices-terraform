output "vms" {
  description = "VM / port / SG / IP。API の稼働完了を意味しない。"
  value = {
    for service, vm in openstack_compute_instance_v2.vm : service => {
      id                = vm.id
      name              = vm.name
      port_id           = openstack_networking_port_v2.vm[service].id
      security_group_id = openstack_networking_secgroup_v2.vm[service].id
      private_ip        = one(openstack_networking_port_v2.vm[service].all_fixed_ips)
      floating_ip       = try(openstack_networking_floatingip_v2.vm[service].address, null)
    }
  }
}
