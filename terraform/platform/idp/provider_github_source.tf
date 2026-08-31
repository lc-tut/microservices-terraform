# GitHub OAuth Source
# github_oauth_client_id が設定されている場合のみ作成する

resource "authentik_source_oauth" "github" {
  count = var.github_oauth_client_id != "" ? 1 : 0

  name          = "GitHub"
  slug          = "github"
  provider_type = "github"

  consumer_key    = var.github_oauth_client_id
  consumer_secret = var.github_oauth_client_secret

  # 既に GitHub アカウントを連携済みのメンバーはログインに使える
  # （authentication.tf の authentik_stage_identification.sources に登録）。
  # 一方 enrollment_flow は null のままにし、未連携ユーザーが GitHub 認証だけで
  # 新規アカウントを作れないようにする（member-enrollment の招待制を維持するため）
  authentication_flow = authentik_flow.lc_cloud_authentication.uuid
  enrollment_flow     = null

  user_matching_mode = "identifier"
}
