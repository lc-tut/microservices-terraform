# state は GCS バケット linuxclub-network-cloud-terraform-state（GCP プロジェクト
# main-vcompute）に置く。state のロックは GCS backend が .tflock オブジェクトの
# 排他作成で行うため、S3 backend の use_lockfile に相当する設定は要らない。
terraform {
  # prefix はディレクトリ構成に合わせている。S3 backend 時代は
  # tfstate/terraform/platform/idp-infra/（ディレクトリ再編前の旧パス）を使って
  # いたが、あれは Polaris に apply 済みの state を参照し続けるための措置だった。
  # バックエンドごと別環境へ移したので、その制約はもう無い。
  backend "gcs" {
    bucket = "linuxclub-network-cloud-terraform-state"
    prefix = "tfstate/terraform/platform/infra/idp-infra"
  }
}
