# 接続先の共有ネットワーク・鍵は参照のみ。サブネットを明示して複数候補を避ける。
data "openstack_networking_subnet_v2" "vm" {
  for_each  = local.vms
  subnet_id = each.value.subnet_id
}

data "openstack_compute_keypair_v2" "vm" {
  for_each = local.vms
  name     = each.value.keypair_name
}

locals {
  vms             = { infra = var.vm_config }
  floating_ip_vms = { for service, vm in local.vms : service => vm if vm.floating_ip_pool != null }
  ingress_rules = merge([
    for service, vm in local.vms : merge(
      { for cidr in vm.ssh_allowed_cidrs : "${service}/ssh/${cidr}" => { service = service, port = 22, cidr = cidr } },
      { for cidr in vm.api_allowed_cidrs : "${service}/api/${cidr}" => { service = service, port = 8080, cidr = cidr } },
      { for cidr in vm.admin_allowed_cidrs : "${service}/admin/${cidr}" => { service = service, port = 8081, cidr = cidr } },
    )
  ]...)
}

resource "openstack_networking_secgroup_v2" "vm" {
  for_each    = local.vms
  name        = "lcn-${each.key}-api-sg"
  description = "Managed by Terraform: lcn-${each.key}-api"
}

resource "openstack_networking_secgroup_rule_v2" "ingress" {
  for_each          = local.ingress_rules
  security_group_id = openstack_networking_secgroup_v2.vm[each.value.service].id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.cidr
}

# platform/infra の既存 VM と同様に明示ポートへ SG / Floating IP を関連付ける。
resource "openstack_networking_port_v2" "vm" {
  for_each              = local.vms
  name                  = "lcn-${each.key}-api"
  network_id            = data.openstack_networking_subnet_v2.vm[each.key].network_id
  admin_state_up        = true
  port_security_enabled = true
  no_security_groups    = false
  security_group_ids    = [openstack_networking_secgroup_v2.vm[each.key].id]

  fixed_ip {
    subnet_id = each.value.subnet_id
  }
}

resource "openstack_compute_instance_v2" "vm" {
  for_each            = local.vms
  name                = "lcn-${each.key}-api"
  flavor_id           = each.value.flavor_id
  key_pair            = data.openstack_compute_keypair_v2.vm[each.key].name
  stop_before_destroy = true

  metadata = {
    managed_by = "terraform"
    service    = "lcn-${each.key}-api"
  }

  # OS 固有パッケージやアプリ、秘密情報はまだ配備しない。
  # yamlencode によって cloud-config を生成し、文字列の直接展開を避ける。
  user_data = "#cloud-config\n${yamlencode({
    ssh_pwauth = false
    write_files = [{
      path        = "/opt/lcn-${each.key}-api/PROVISIONING.txt"
      owner       = "root:root"
      permissions = "0644"
      content     = "VM prepared by middle-api-infra/openstack. Application deployment is pending.\n"
    }]
  })}"

  block_device {
    uuid                  = each.value.image_id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = each.value.root_volume_size
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.vm[each.key].id
  }

  lifecycle {
    prevent_destroy = true
    # SG は明示ポート側が所有する（既存 platform/infra と同じ）。
    ignore_changes = [security_groups]
  }
}

resource "openstack_networking_floatingip_v2" "vm" {
  for_each    = local.floating_ip_vms
  pool        = each.value.floating_ip_pool
  description = "lcn-${each.key}-api"
}

resource "openstack_networking_floatingip_associate_v2" "vm" {
  for_each    = local.floating_ip_vms
  floating_ip = openstack_networking_floatingip_v2.vm[each.key].address
  port_id     = openstack_networking_port_v2.vm[each.key].id
}
