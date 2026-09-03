locals {
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    ck_image_tag          = var.ck_image_tag
    mariadb_image         = var.mariadb_image
    influxdb_image        = var.influxdb_image
    mariadb_root_password = random_password.mariadb_root.result
    ck_db_password        = random_password.ck_db.result
    keystone_auth_url     = var.keystone_auth_url
    os_admin_username     = var.os_admin_username
    os_admin_password     = var.os_admin_password
    os_admin_project_name = var.os_admin_project_name
    os_region_name        = var.os_region_name
    prometheus_url        = var.prometheus_url
  })
}

resource "openstack_compute_instance_v2" "cloudkitty" {
  name        = var.instance_name
  flavor_name = var.flavor_name
  key_pair    = data.openstack_compute_keypair_v2.cloudkitty.name
  user_data   = local.cloud_init

  block_device {
    uuid                  = data.openstack_images_image_v2.base.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.root_volume_size
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.cloudkitty.id
  }

  lifecycle {
    # idp-infra/compute.tf と同じ理由（SG はポート側で管理、user_data 変更は
    # 明示的に -replace で作り直す）
    ignore_changes = [user_data, security_groups]
  }
}
