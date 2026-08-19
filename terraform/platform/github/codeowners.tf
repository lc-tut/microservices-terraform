# Tier 2 の CODEOWNERS エントリを Terraform で管理する
# catalog/ に team/project が追加されると apply 時に .github/CODEOWNERS が自動更新される
#
# catalog/teams/ と catalog/projects/ の outputs を data source で参照するため、
# それらのスタックが先に apply されている必要がある（Phase 3 で apply-phase3 が担当）

locals {
  # catalog/teams/<name>/outputs.tf の output "lead_team" を集約
  # Phase 3 以降に各スタックの remote state から取得する予定
  # 現時点は空マップ（Phase 1 ではチーム未作成）
  catalog_teams    = {}
  catalog_projects = {}
}

resource "codeowners_file" "main" {
  repository_name  = var.github_repo
  repository_owner = var.github_org
  branch           = "main"

  # Tier 1（静的 — .github/CODEOWNERS の先頭行と一致させる）
  rules {
    pattern = "/terraform/platform/"
    owners  = ["@lc-tut/circle-admin"]
  }

  rules {
    pattern = "/terraform/modules/"
    owners  = ["@lc-tut/circle-admin"]
  }

  # Tier 2（動的 — catalog/ apply 時に自動追加される）
  dynamic "rules" {
    for_each = local.catalog_teams
    content {
      pattern = "/terraform/catalog/teams/${rules.key}/"
      owners  = ["@lc-tut/circle-admin", "@lc-tut/${rules.key}-lead"]
    }
  }

  dynamic "rules" {
    for_each = local.catalog_projects
    content {
      pattern = "/terraform/catalog/projects/${rules.key}/"
      owners  = concat(["@lc-tut/circle-admin"], rules.value.owners)
    }
  }

  # Tier 3（静的デフォルト）
  rules {
    pattern = "/terraform/workspaces/"
    owners  = ["@lc-tut/all-leads"]
  }
}
