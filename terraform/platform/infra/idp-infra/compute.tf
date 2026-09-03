locals {
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    postgres_image     = var.postgres_image
    authentik_image    = var.authentik_image
    pg_pass            = random_password.postgres.result
    secret_key         = random_password.secret_key.result
    bootstrap_password = random_password.bootstrap_password.result
    bootstrap_token    = random_id.bootstrap_token.hex
    email_host         = var.authentik_email_host
    email_port         = tostring(var.authentik_email_port)
    email_username     = var.authentik_email_username
    email_password     = var.authentik_email_password
    email_use_tls      = var.authentik_email_use_tls ? "true" : "false"
    email_use_ssl      = var.authentik_email_use_ssl ? "true" : "false"
    email_from         = var.authentik_email_from
  })
}

resource "openstack_compute_instance_v2" "authentik" {
  name        = var.instance_name
  flavor_name = var.flavor_name
  key_pair    = data.openstack_compute_keypair_v2.authentik.name
  user_data   = local.cloud_init

  # SG は明示ポート(openstack_networking_port_v2.authentik)側で管理する。
  # instance の security_groups は Nova がポートの SG を読み戻すため
  # 設定せず ignore_changes に入れる（設定すると永久 diff / 二重管理になる）。

  block_device {
    uuid                  = data.openstack_images_image_v2.base.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.root_volume_size
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.authentik.id
  }

  lifecycle {
    # - user_data: cloud-init 変更で作り直さない（作り直しは明示的に -replace）
    # - security_groups: Nova がポートの SG を読み戻すため無視（SG はポート側で管理）
    ignore_changes = [user_data, security_groups]
  }
}
