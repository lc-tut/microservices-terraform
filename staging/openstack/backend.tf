terraform {
  backend "gcs" {
    bucket = "linuxclub-network-cloud-terraform-state"
    prefix = "tfstate/staging/openstack"
  }
}
