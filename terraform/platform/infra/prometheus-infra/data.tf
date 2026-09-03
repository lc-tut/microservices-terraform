data "openstack_images_image_v2" "base" {
  name        = var.image_name
  most_recent = true
}

data "openstack_networking_network_v2" "private" {
  name = var.private_network_name
}

data "openstack_networking_subnet_v2" "private" {
  network_id = data.openstack_networking_network_v2.private.id
}

data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}
