terraform {
  required_version = "~> 1.10"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2026.5"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
  # AUTHENTIK_URL / AUTHENTIK_TOKEN 環境変数でも設定可
}

# 全メンバーが所属する基本グループ
# enrollment 完了時に authentik_stage_user_write がここに自動追加する
resource "authentik_group" "all_members" {
  name         = "all-members"
  is_superuser = false
}
