terraform {
  required_version = "~> 1.10"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    codeowners = {
      source  = "form3tech-oss/codeowners"
      version = "~> 0.3"
    }
  }
}

provider "github" {
  owner = var.github_org
  # GITHUB_TOKEN 環境変数から自動読み込み
}

provider "codeowners" {
  # GITHUB_TOKEN 環境変数から自動読み込み
}
