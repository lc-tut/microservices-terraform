# Discord OAuth Source
# discord_oauth_client_id が設定されている場合のみ作成する

resource "authentik_source_oauth" "discord" {
  count = var.discord_oauth_client_id != "" ? 1 : 0

  name          = "Discord"
  slug          = "discord"
  provider_type = "discord"

  consumer_key    = var.discord_oauth_client_id
  consumer_secret = var.discord_oauth_client_secret

  # GitHub 連携と同じ方針: 連携済みメンバーはログインに使えるが、
  # enrollment_flow は null のままにし Discord 認証だけでの新規アカウント作成は許可しない
  authentication_flow = authentik_flow.lc_cloud_authentication.uuid
  enrollment_flow     = null

  user_matching_mode = "identifier"
}
