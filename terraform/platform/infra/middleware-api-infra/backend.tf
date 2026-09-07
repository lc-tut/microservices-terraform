# 既存 platform/infra と同じ GCS bucket、専用 prefix を使う。
# 認証情報到着前の検証では init -backend=false を使う。
terraform {
  backend "gcs" {
    bucket = "linuxclub-network-cloud-terraform-state"
    prefix = "tfstate/terraform/platform/infra/middleware-api-infra"
  }
}
