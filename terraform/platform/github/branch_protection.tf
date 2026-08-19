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
    push_allowances = [
      "/lc-tut/circle-admin",
    ]
  }
}
