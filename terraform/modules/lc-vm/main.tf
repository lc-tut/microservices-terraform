# network/subnet は catalog/projects/<project_name>/ が作成済みのものを参照する
# (openstack_networking_port_v2 の明示作成は禁止方針のため、instance の
# network{} ブロックで暗黙ポートを使う。12-openstack-resources.md 参照)。
data "openstack_networking_network_v2" "project" {
  name = var.project_name
}

data "openstack_networking_subnet_v2" "project" {
  name = var.project_name
}

data "openstack_compute_flavor_v2" "this" {
  name = var.flavor
}

data "openstack_images_image_v2" "this" {
  name        = var.image
  most_recent = true
}

resource "openstack_networking_secgroup_v2" "this" {
  name        = "${var.name}-sg"
  description = "modules/lc-vm が ${var.name} 用に作成"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  count             = var.allow_ssh_from_project_subnet ? 1 : 0
  security_group_id = openstack_networking_secgroup_v2.this.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = data.openstack_networking_subnet_v2.project.cidr
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  count             = var.allow_ssh_from_project_subnet ? 1 : 0
  security_group_id = openstack_networking_secgroup_v2.this.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = data.openstack_networking_subnet_v2.project.cidr
}

resource "openstack_networking_secgroup_rule_v2" "extra" {
  for_each = { for idx, rule in var.security_group_rules : idx => rule }

  security_group_id = openstack_networking_secgroup_v2.this.id
  direction         = each.value.direction
  ethertype         = each.value.ethertype
  protocol          = each.value.protocol
  port_range_min    = each.value.port_range_min
  port_range_max    = each.value.port_range_max
  remote_ip_prefix  = each.value.remote_ip_prefix
}

# CA trust設定(常に先頭パート) + アプリ固有 user_data(任意) を
# multipart MIME で合成する。
data "cloudinit_config" "this" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "10-ssh-ca-trust.yaml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/ca-trust.yaml.tftpl", {
      ssh_ca_public_key = var.ssh_ca_public_key
    })
  }

  dynamic "part" {
    for_each = var.user_data != "" ? [var.user_data] : []
    content {
      filename     = "20-user-data"
      content_type = "text/cloud-config"
      content      = part.value
    }
  }
}

# ボリュームを独立したリソースとして作成する(instance に inline block_device で
# 作らせない)。resize・snapshot・instance 作り直し後の付け替えが state 上で
# 独立して行えるようにするため(12-openstack-resources.md「lc-vm」の意図)。
resource "openstack_blockstorage_volume_v3" "root" {
  name        = "${var.name}-root"
  size        = var.volume_size_gb
  image_id    = data.openstack_images_image_v2.this.id
  volume_type = var.volume_type
}

resource "openstack_compute_instance_v2" "this" {
  name            = var.name
  flavor_id       = data.openstack_compute_flavor_v2.this.id
  security_groups = [openstack_networking_secgroup_v2.this.name]
  user_data       = data.cloudinit_config.this.rendered
  metadata        = var.metadata

  # 起動元は事前作成した volume(既存 volume からの boot)。
  # destination_type=volume だが source_type=volume なので Cinder は
  # 新規作成せず、上の openstack_blockstorage_volume_v3.root をそのまま使う。
  block_device {
    uuid                  = openstack_blockstorage_volume_v3.root.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  network {
    uuid = data.openstack_networking_network_v2.project.id
  }

  lifecycle {
    # cloud-init 変更で作り直さない(作り直しは明示的に -replace)。
    # 他の infra root(idp-infra 等)と同じ方針。
    ignore_changes = [user_data]
  }
}
