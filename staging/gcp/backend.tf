# state は本番と同じ GCS バケット（GCP プロジェクト main-vcompute）に置く。
# local/gcp-devstack/ がローカル state なのは「各自の手元にひとつずつ建てる」
# ものだからで、staging は全員が同じ1組を共有するためリモートに置く。
# ロックは GCS backend が .tflock オブジェクトの排他作成で行う。
terraform {
  backend "gcs" {
    bucket = "linuxclub-network-cloud-terraform-state"
    prefix = "tfstate/staging/gcp"
  }
}
