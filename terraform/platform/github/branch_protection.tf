# main ブランチ保護ルール
# - PR 必須（CODEOWNERS レビュー 1 名以上、古いレビューは無効化）
# - CI ステータスチェック必須（validate / plan が通ること）
# - 直接 push は circle-admin チームのみ許可（通常の開発は PR 経由）

resource "github_branch_protection" "main" {
  repository_id = var.github_repo
  pattern       = "main"

  required_pull_request_reviews {
    required_approving_review_count = 1
    require_code_owner_reviews      = true
    dismiss_stale_reviews           = true
  }

  required_status_checks {
    strict = true
    contexts = [
      "validate",
      "plan",
    ]
  }

  enforce_admins        = false
  allows_deletions      = false
  allows_force_pushes   = false

  restrict_pushes {
    # push_allowances にはスラッグ文字列ではなく GraphQL node_id を渡す必要がある
    # リソース参照にすることで apply 順序の依存も自動解決される
    push_allowances = [
      github_team.circle_admin.node_id,
    ]
  }
}
