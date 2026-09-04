terraform {
  required_version = "~> 1.10"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.12"
    }
  }
}

provider "harbor" {
  url      = var.harbor_url
  username = "admin"
  password = var.harbor_admin_password
  # HARBOR_URL / HARBOR_USERNAME / HARBOR_PASSWORD 環境変数でも設定可
}
