terraform {
  backend "s3" {
    bucket                      = "linuxclub-tfstate"
    key                         = "tfstate/terraform/platform/members/terraform.tfstate"
    region                      = "us-east-1"
    use_lockfile                = true
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
