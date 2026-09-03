# DB パスワードは Terraform で新規生成する。state にのみ保存し、平文コミットしない。
# terraform/platform/infra/idp-infra/secrets.tf と同じ方針。
resource "random_password" "mariadb_root" {
  length  = 32
  special = false
}

resource "random_password" "ck_db" {
  length  = 32
  special = false
}
