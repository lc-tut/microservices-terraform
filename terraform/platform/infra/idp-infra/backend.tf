terraform {
  # terraform/platform/idp/ と同じ MinIO(ローカル) / Ceph RGW(本番 CI) の
  # S3 互換バックエンドを共有する。key だけ分ける。
  #
  # key は terraform/platform/idp-infra/（ディレクトリ再編前の旧パス）のまま
  # 意図的に変更していない。Polaris に実際に apply 済みの本番 state を
  # 参照しているため、ディレクトリ移動に合わせて key も変えると
  # state マイグレーションが必要になる（このリポジトリからは実施できない）。
  backend "s3" {
    bucket = "linuxclub-tfstate"
    key    = "tfstate/terraform/platform/idp-infra/terraform.tfstate"
    region = "us-east-1"

    use_lockfile                = true
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
