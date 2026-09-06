terraform {
  required_version = "~> 1.10"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

provider "openstack" {
  auth_url = var.os_auth_url
}
