terraform {
  required_version = "~> 1.10"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2026.5"
    }
  }
}
