# 明示的に渡されなかった秘密値は Terraform が生成する。
# 値は state（GCS バケット）にのみ入るので、バケットの権限管理がそのまま
# これらの実質的なアクセス制御になる（platform/openstack/images/ssh_ca.tf と同じ方針）。

resource "random_password" "harbor_admin" {
  length  = 24
  special = true
  # Harbor の install.sh は harbor.yml を YAML として読むため、
  # クォートが要る文字を避ける
  override_special = "-_.@"
}

resource "random_password" "authentik_secret_key" {
  length  = 50
  special = false
}

resource "random_password" "authentik_bootstrap_password" {
  length           = 24
  special          = true
  override_special = "-_.@"
}

resource "random_id" "authentik_bootstrap_token" {
  byte_length = 32
}

resource "random_password" "infra_db" {
  length  = 32
  special = false
}

# 一覧カーソルの署名鍵。レプリカ間で同じ値であることが要件
# （lcn-infra-api/deploy/secret.example.yaml: 違う値だと、別のレプリカが
# 発行したカーソルを invalid_cursor で弾く）
resource "random_password" "cursor_secret" {
  length  = 32
  special = false
}

locals {
  infra_db_password = random_password.infra_db.result
  cursor_secret     = random_password.cursor_secret.result

  harbor_admin_password        = var.harbor_admin_password != "" ? var.harbor_admin_password : random_password.harbor_admin.result
  authentik_secret_key         = var.authentik_secret_key != "" ? var.authentik_secret_key : random_password.authentik_secret_key.result
  authentik_bootstrap_password = var.authentik_bootstrap_password != "" ? var.authentik_bootstrap_password : random_password.authentik_bootstrap_password.result
  authentik_bootstrap_token    = var.authentik_bootstrap_token != "" ? var.authentik_bootstrap_token : random_id.authentik_bootstrap_token.hex
}
