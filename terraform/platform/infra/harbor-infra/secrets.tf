# Harbor admin パスワード・内蔵 DB パスワードは Terraform で新規生成する。
# state にのみ保存し、平文コミットしない（terraform/platform/infra/idp-infra/secrets.tf
# と同じ方針）。
resource "random_password" "harbor_admin" {
  length  = 24
  special = false
}

resource "random_password" "harbor_db" {
  length  = 32
  special = false
}
