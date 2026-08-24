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
  # ob-og/alumni 配下の auto-gen-*.yaml は .enc 管理。apply 前に scripts/decrypt-members.sh で
  # 同名の平文ファイル（.gitignore 対象）へ復号しておく。フォルダが存在しなくても
  # fileset は空集合を返すためエラーにはならない
  statuses = ["active", "ob-og", "alumni"]

  cohort_files_by_status = {
    for s in local.statuses : s => fileset("${path.module}/${s}", "*/members.yaml")
  }

  # status・grad_year（コホートフォルダ名から抽出）を付与する。
  # active 以外は members.yaml 上の role を無視し status 名で上書き
  members_list = flatten([
    for status in local.statuses : [
      for f in local.cohort_files_by_status[status] : [
        for m in yamldecode(file("${path.module}/${status}/${f}")).members : merge(m, {
          status    = status
          grad_year = tonumber(regex("grad-(\\d+)", dirname(f))[0])
          role      = status == "active" ? m.role : status
        })
      ]
    ]
  ])

  members_by_id = {
    for m in local.members_list : m.id => m
  }

  # members_secrets.yaml（SOPS復号済み）から email・student_id を読み込む
  # CI では apply 前に sops --decrypt で復号しておくこと
  secrets = sensitive(merge(flatten([
    for status in local.statuses : [
      for f in local.cohort_files_by_status[status] :
      yamldecode(file("${path.module}/${status}/${dirname(f)}/members_secrets.yaml")).members
    ]
  ])...))

  # enrollment 完了済み: id → {username, display_name}
  # active は平文、ob-og/alumni は .enc から復号済みの同名平文ファイルを読む（内容形式は同じ）
  _auto_gen_maps = flatten([
    for status in local.statuses : [
      for f in fileset("${path.module}/${status}", "*/auto-gen-members.yaml") :
      try(yamldecode(file("${path.module}/${status}/${f}")), {})
    ]
  ])
  auto_gen = length(local._auto_gen_maps) > 0 ? merge(local._auto_gen_maps...) : {}

  # GitHub 連携済み: id → github_username
  # active は既存のフラットファイル、ob-og/alumni はコホートフォルダ単位の .enc 復号ファイルから読む
  _github_username_maps = concat(
    [try(yamldecode(file("${path.module}/auto-gen-github-usernames.yaml")), {})],
    flatten([
      for status in ["ob-og", "alumni"] : [
        for f in fileset("${path.module}/${status}", "*/auto-gen-github-usernames.yaml") :
        try(yamldecode(file("${path.module}/${status}/${f}")), {})
      ]
    ]),
  )
  github_usernames = merge(local._github_username_maps...)
}
