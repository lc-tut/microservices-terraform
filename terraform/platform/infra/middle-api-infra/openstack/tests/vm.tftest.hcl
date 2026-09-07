# mock provider のみを使い、実 OpenStack / GCS を操作しない。
mock_provider "openstack" {
  mock_data "openstack_networking_subnet_v2" {
    defaults = { network_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" }
  }
}
variables {
  vm_config = {
    image_id          = "11111111-1111-1111-1111-111111111111"
    flavor_id         = "test-flavor"
    subnet_id         = "22222222-2222-2222-2222-222222222222"
    keypair_name      = "test-key"
    root_volume_size  = 40
    ssh_allowed_cidrs = ["192.0.2.10/32"]
  }
}
run "private_vm" {
  command = plan
  assert {
    condition     = toset(keys(openstack_compute_instance_v2.vm)) == toset(["infra"]) && openstack_compute_instance_v2.vm["infra"].name == "lcn-infra-api"
    error_message = "この root は lcn-infra-api 1台だけを管理します。"
  }
  assert {
    condition     = length(openstack_networking_floatingip_v2.vm) == 0 && length(openstack_networking_floatingip_associate_v2.vm) == 0
    error_message = "既定で Floating IP を作成してはいけません。"
  }
  assert {
    condition = length(openstack_networking_secgroup_rule_v2.ingress) == 1 && alltrue([
      for rule in openstack_networking_secgroup_rule_v2.ingress :
      rule.port_range_min == 22 && rule.port_range_max == 22 && rule.remote_ip_prefix == "192.0.2.10/32"
    ])
    error_message = "既定の受信許可は管理元からの SSH だけです。"
  }
  assert {
    condition = alltrue([for port in openstack_networking_port_v2.vm :
      port.network_id == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" && port.port_security_enabled && !port.no_security_groups && length(port.security_group_ids) == 1
    ])
    error_message = "指定 subnet の network 上で専用 SG を使う必要があります。"
  }
  assert {
    condition     = yamldecode(trimprefix(openstack_compute_instance_v2.vm["infra"].user_data, "#cloud-config\n")).ssh_pwauth == false
    error_message = "SSH パスワード認証を無効にします。"
  }
}
run "explicit_ingress_and_floating_ip" {
  command = plan
  variables {
    vm_config = {
      image_id          = "11111111-1111-1111-1111-111111111111"
      flavor_id         = "test-flavor"
      subnet_id         = "22222222-2222-2222-2222-222222222222"
      keypair_name      = "test-key"
      root_volume_size  = 40
      ssh_allowed_cidrs = ["192.0.2.10/32"]
      api_allowed_cidrs = ["192.0.2.20/32"]
      floating_ip_pool  = "test-external"
    }
  }
  assert {
    condition     = toset(keys(openstack_networking_floatingip_v2.vm)) == toset(["infra"]) && toset(keys(openstack_networking_floatingip_associate_v2.vm)) == toset(["infra"])
    error_message = "対象 VM にだけ Floating IP を作成・関連付けます。"
  }
  assert {
    condition = length(openstack_networking_secgroup_rule_v2.ingress) == 2 && alltrue([
      for rule in openstack_networking_secgroup_rule_v2.ingress :
      rule.port_range_min == rule.port_range_max && (
        (rule.port_range_min == 22 && rule.remote_ip_prefix == "192.0.2.10/32") ||
        (rule.port_range_min == 8080 && rule.remote_ip_prefix == "192.0.2.20/32")
      )
    ])
    error_message = "明示した送信元とポートの組だけを許可します。"
  }
}
run "reject_world_open_ssh" {
  command = plan
  variables {
    vm_config = {
      image_id          = "11111111-1111-1111-1111-111111111111"
      flavor_id         = "test-flavor"
      subnet_id         = "22222222-2222-2222-2222-222222222222"
      keypair_name      = "test-key"
      root_volume_size  = 40
      ssh_allowed_cidrs = ["0.0.0.0/0"]
    }
  }
  expect_failures = [var.vm_config]
}
run "reject_infra_admin_port" {
  command = plan
  variables {
    vm_config = {
      image_id            = "11111111-1111-1111-1111-111111111111"
      flavor_id           = "test-flavor"
      subnet_id           = "22222222-2222-2222-2222-222222222222"
      keypair_name        = "test-key"
      root_volume_size    = 40
      ssh_allowed_cidrs   = ["192.0.2.10/32"]
      admin_allowed_cidrs = ["192.0.2.30/32"]
    }
  }
  expect_failures = [var.vm_config]
}
