# GitHub OAuth Source（ログイン用ではなくアカウント紐づけ専用）
# github_oauth_client_id が設定されている場合のみ作成する

resource "authentik_source_oauth" "github" {
  count = var.github_oauth_client_id != "" ? 1 : 0

  name          = "GitHub"
  slug          = "github"
  provider_type = "github"

  consumer_key    = var.github_oauth_client_id
  consumer_secret = var.github_oauth_client_secret

  # ログインには使わない（Connected Sources 画面から任意で紐づけ）
  authentication_flow = null
  enrollment_flow     = null

  user_matching_mode = "identifier"
}
