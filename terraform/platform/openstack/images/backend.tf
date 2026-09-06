# state は GCS バケット linuxclub-network-cloud-terraform-state（GCP プロジェクト
# main-vcompute）に置く。state のロックは GCS backend が .tflock オブジェクトの
# 排他作成で行うため、S3 backend の use_lockfile に相当する設定は要らない。
terraform {
  # prefix はディレクトリ構成に合わせている。S3 backend 時代の key は
  # tfstate/terraform/platform/images/ という旧パスのままだったが、
  # バックエンドごと別環境へ移したので揃えた。
  backend "gcs" {
    bucket = "linuxclub-network-cloud-terraform-state"
    prefix = "tfstate/terraform/platform/openstack/images"
  }
}
