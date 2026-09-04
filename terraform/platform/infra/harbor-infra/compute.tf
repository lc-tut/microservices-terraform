locals {
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    harbor_version        = var.harbor_version
    harbor_with_trivy     = var.harbor_with_trivy
    harbor_hostname       = var.harbor_hostname
    harbor_admin_password = random_password.harbor_admin.result
    harbor_db_password    = random_password.harbor_db.result
  })
}

resource "openstack_compute_instance_v2" "harbor" {
  name        = var.instance_name
  flavor_name = var.flavor_name
  key_pair    = openstack_compute_keypair_v2.harbor.name
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
    port = openstack_networking_port_v2.harbor.id
  }

  lifecycle {
    # idp-infra/compute.tf と同じ理由（SG はポート側で管理、user_data 変更は
    # 明示的に -replace で作り直す）
    ignore_changes = [user_data, security_groups]
  }
}
