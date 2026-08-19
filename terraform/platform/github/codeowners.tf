locals {
  # catalog/teams/<name>/outputs.tf の output "lead_team" を集約
  # Phase 3 以降に各スタックの remote state から取得する予定
  # 現時点は空マップ（Phase 1 ではチーム未作成）
  catalog_teams    = {}
  catalog_projects = {}

  codeowners_lines = concat(
    [
      "# Tier 1 — platform & modules（Terraform 管理）",
      "/terraform/platform/ @lc-tut/circle-admin",
      "/terraform/modules/  @lc-tut/circle-admin",
      "",
      "# Tier 2 — catalog（Terraform apply 時に自動更新）",
    ],
    [for name, _ in local.catalog_teams :
      "/terraform/catalog/teams/${name}/ @lc-tut/circle-admin @lc-tut/${name}-lead"
    ],
    [for name, val in local.catalog_projects :
      "/terraform/catalog/projects/${name}/ ${join(" ", concat(["@lc-tut/circle-admin"], val.owners))}"
    ],
    [
      "",
      "# Tier 3 — workspaces（デフォルトフォールバック）",
      "/terraform/workspaces/ @lc-tut/all-leads",
    ]
  )
}

resource "github_repository_file" "codeowners" {
  repository          = var.github_repo
  branch              = "main"
  file                = ".github/CODEOWNERS"
  content             = join("\n", local.codeowners_lines)
  commit_message      = "chore: update CODEOWNERS [skip ci]"
  overwrite_on_create = true
}
