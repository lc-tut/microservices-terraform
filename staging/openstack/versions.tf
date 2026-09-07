terraform {
  required_version = ">= 1.6"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

# 認証は OS_* 環境変数から。staging/terraform/tf.sh が staging の DevStack を
# 指すように設定する
provider "openstack" {
  auth_url = var.os_auth_url
}
