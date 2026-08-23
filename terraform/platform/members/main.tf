terraform {
  required_version = "~> 1.10"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2026.5"
    }
  }
}

provider "github" {
  owner = var.github_org
  token = var.github_token
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

locals {
  cohort_files = fileset("${path.module}/active", "*/members.yaml")

  # id・role のフラットリスト（全コホート）
  members_list = flatten([
    for f in local.cohort_files :
    yamldecode(file("${path.module}/active/${f}")).members
  ])

  members_by_id = {
    for m in local.members_list : m.id => m
  }

  # members_secrets.yaml（SOPS復号済み）から email・student_id を読み込む
  # CI では apply 前に sops --decrypt で復号しておくこと
  secrets = sensitive(merge([
    for f in local.cohort_files :
    yamldecode(file(
      "${path.module}/active/${dirname(f)}/members_secrets.yaml"
    )).members
  ]...))

  # enrollment 完了済み: id → {username, display_name}
  # ファイルがコメントのみ（null）の場合は {} にフォールバック
  _auto_gen_maps = [
    for f in fileset("${path.module}/active", "*/auto-gen-members.yaml") :
    try(yamldecode(file("${path.module}/active/${f}")), {})
  ]
  auto_gen = length(local._auto_gen_maps) > 0 ? merge(local._auto_gen_maps...) : {}

  # GitHub 連携済み: id → github_username
  github_usernames = try(
    yamldecode(file("${path.module}/auto-gen-github-usernames.yaml")),
    {}
  )
}
