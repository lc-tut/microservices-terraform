# 全 run が mock provider を使う。OpenStack / GCS への認証・VM 作成は行わない。
mock_provider "openstack" {
  mock_data "openstack_networking_subnet_v2" {
    defaults = {
      network_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }
}

variables {
  vm_config = {
    infra = {
      image_id          = "11111111-1111-1111-1111-111111111111"
      flavor_id         = "test-flavor"
      subnet_id         = "22222222-2222-2222-2222-222222222222"
      keypair_name      = "test-key"
      root_volume_size  = 40
      ssh_allowed_cidrs = ["192.0.2.10/32"]
    }
    billing = {
      image_id          = "11111111-1111-1111-1111-111111111111"
      flavor_id         = "test-flavor"
      subnet_id         = "22222222-2222-2222-2222-222222222222"
      keypair_name      = "test-key"
      root_volume_size  = 40
      ssh_allowed_cidrs = ["192.0.2.10/32"]
    }
  }
}

run "private_vms" {
  command = plan

  assert {
    condition     = toset(keys(openstack_compute_instance_v2.vm)) == toset(["infra", "billing"])
    error_message = "infra と billing の2台を作成する必要があります。"
  }
  assert {
    condition     = length(openstack_networking_floatingip_v2.vm) == 0 && length(openstack_networking_floatingip_associate_v2.vm) == 0
    error_message = "既定で Floating IP を作成してはいけません。"
  }
  assert {
    condition = length(openstack_networking_secgroup_rule_v2.ingress) == 2 && alltrue([
      for rule in openstack_networking_secgroup_rule_v2.ingress :
      rule.port_range_min == 22 && rule.port_range_max == 22 && rule.remote_ip_prefix == "192.0.2.10/32"
    ])
    error_message = "既定の受信許可は指定した管理元からの SSH のみです。"
  }
  assert {
    condition = alltrue([for port in openstack_networking_port_v2.vm :
      port.network_id == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" && port.port_security_enabled && !port.no_security_groups && length(port.security_group_ids) == 1
    ])
    error_message = "VM ポートは指定 subnet の network 上で専用 SG を使う必要があります。"
  }
  assert {
    condition = alltrue([for vm in openstack_compute_instance_v2.vm :
      yamldecode(trimprefix(vm.user_data, "#cloud-config\n")).ssh_pwauth == false
    ])
    error_message = "cloud-init は SSH パスワード認証を無効にします。"
  }
}

run "explicit_ingress_and_floating_ip" {
  command = plan
  variables {
    vm_config = {
      infra = {
        image_id          = "11111111-1111-1111-1111-111111111111"
        flavor_id         = "test-flavor"
        subnet_id         = "22222222-2222-2222-2222-222222222222"
        keypair_name      = "test-key"
        root_volume_size  = 40
        ssh_allowed_cidrs = ["192.0.2.10/32"]
        api_allowed_cidrs = ["192.0.2.20/32"]
      }
      billing = {
        image_id            = "11111111-1111-1111-1111-111111111111"
        flavor_id           = "test-flavor"
        subnet_id           = "22222222-2222-2222-2222-222222222222"
        keypair_name        = "test-key"
        root_volume_size    = 60
        ssh_allowed_cidrs   = ["192.0.2.10/32"]
        api_allowed_cidrs   = ["192.0.2.20/32"]
        admin_allowed_cidrs = ["192.0.2.30/32"]
        floating_ip_pool    = "test-external"
      }
    }
  }
  assert {
    condition     = toset(keys(openstack_networking_floatingip_v2.vm)) == toset(["billing"]) && toset(keys(openstack_networking_floatingip_associate_v2.vm)) == toset(["billing"])
    error_message = "Floating IP は指定された billing にのみ割り当てます。"
  }
  assert {
    condition = length(openstack_networking_secgroup_rule_v2.ingress) == 5 && alltrue([
      for rule in openstack_networking_secgroup_rule_v2.ingress :
      rule.port_range_min == rule.port_range_max && (
        (rule.port_range_min == 22 && rule.remote_ip_prefix == "192.0.2.10/32") ||
        (rule.port_range_min == 8080 && rule.remote_ip_prefix == "192.0.2.20/32") ||
        (rule.port_range_min == 8081 && rule.remote_ip_prefix == "192.0.2.30/32")
      )
    ])
    error_message = "明示した送信元と API ポートの組だけを許可する必要があります。"
  }
}

run "reject_world_open_ssh" {
  command = plan
  variables {
    vm_config = {
      for service in ["infra", "billing"] : service => {
        image_id          = "11111111-1111-1111-1111-111111111111"
        flavor_id         = "test-flavor"
        subnet_id         = "22222222-2222-2222-2222-222222222222"
        keypair_name      = "test-key"
        root_volume_size  = 40
        ssh_allowed_cidrs = ["0.0.0.0/0"]
      }
    }
  }
  expect_failures = [var.vm_config]
}

run "reject_infra_admin_port" {
  command = plan
  variables {
    vm_config = {
      for service in ["infra", "billing"] : service => {
        image_id            = "11111111-1111-1111-1111-111111111111"
        flavor_id           = "test-flavor"
        subnet_id           = "22222222-2222-2222-2222-222222222222"
        keypair_name        = "test-key"
        root_volume_size    = 40
        ssh_allowed_cidrs   = ["192.0.2.10/32"]
        admin_allowed_cidrs = ["192.0.2.30/32"]
      }
    }
  }
  expect_failures = [var.vm_config]
}
