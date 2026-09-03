terraform {
  required_version = "~> 1.10"

  required_providers {
    restapi = {
      source                = "Mastercard/restapi"
      version               = "~> 3.0"
      configuration_aliases = [restapi.cloudkitty]
    }
  }
}
