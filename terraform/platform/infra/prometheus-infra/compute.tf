locals {
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    prometheus_image                   = var.prometheus_image
    prometheus_retention               = var.prometheus_retention
    openstack_exporter_image           = var.openstack_exporter_image
    openstack_exporter_scrape_interval = var.openstack_exporter_scrape_interval
    keystone_auth_url                  = var.keystone_auth_url
    os_admin_username                  = var.os_admin_username
    os_admin_password                  = var.os_admin_password
    os_admin_project_name              = var.os_admin_project_name
    os_region_name                     = var.os_region_name
  })
}

resource "openstack_compute_instance_v2" "prometheus" {
  name        = var.instance_name
  flavor_name = var.flavor_name
  key_pair    = openstack_compute_keypair_v2.prometheus.name
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
    port = openstack_networking_port_v2.prometheus.id
  }

  lifecycle {
    ignore_changes = [user_data, security_groups]
  }
}
