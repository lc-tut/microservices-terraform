# Authentik の秘密情報は Terraform で新規生成する（ローカル開発用
# local/authentik/.env の値は使い回さない）。state に保存され、outputs 経由で
# 取り出せる。state バックエンドは MinIO/Ceph の S3 のみ、平文コミットはしない。

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "secret_key" {
  length  = 50
  special = false
}

# akadmin（ユーザー名 akadmin、既定メール root@example.com）の初期ログインパスワード
resource "random_password" "bootstrap_password" {
  length  = 24
  special = false
}

# 起動時に akadmin 用として自動発行される API トークン。
# terraform/platform/idp/ の AUTHENTIK_TOKEN / GitHub Secret にそのまま使える。
resource "random_id" "bootstrap_token" {
  byte_length = 32
}
