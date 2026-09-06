# グループ名の命名規則を固定するテスト。
#
# この名前は lcn-infra-api との契約になっている。同 API は
# X-authentik-groups に入ってくる "team-web-member" を分解して
# 「web チームの member」と判定しており、判断材料はこれしかない。
#
# prefix・区切り文字・並び順を変えると Terraform 側は何も壊れないまま
# API の認可だけが黙って壊れるため、ここで形式を固定して
# 変更が CI で落ちるようにしている。
#
# 命名規則を意図的に変える場合は、このテストと lcn-infra-api を
# 同じタイミングで直すこと。テストだけ通して先に進めないこと。
#
# provider を持たないモジュールなので、認証情報なしで実行できる:
#   cd terraform/modules/lc-role-map && terraform init -backend=false && terraform test

variables {
  scope_type = "team"
  scope_name = "web"
}

run "team_scope" {
  assert {
    condition     = output.group_names["owner"] == "team-web-owner"
    error_message = "team スコープの owner グループ名が team-<name>-owner ではなくなっている（lcn-infra-api の認可が壊れる）"
  }

  assert {
    condition     = output.group_names["member"] == "team-web-member"
    error_message = "team スコープの member グループ名が team-<name>-member ではなくなっている（lcn-infra-api の認可が壊れる）"
  }

  assert {
    condition     = output.group_names["viewer"] == "team-web-viewer"
    error_message = "team スコープの viewer グループ名が team-<name>-viewer ではなくなっている（lcn-infra-api の認可が壊れる）"
  }
}

run "project_scope" {
  variables {
    scope_type = "project"
    scope_name = "web-frontend"
  }

  # プロジェクトは prefix が proj。scope_name 自体にハイフンが入るため、
  # API 側は「最後のハイフンでロールを切り出す」必要がある。
  assert {
    condition     = output.group_names["member"] == "proj-web-frontend-member"
    error_message = "project スコープのグループ名が proj-<name>-<role> ではなくなっている（lcn-infra-api の認可が壊れる）"
  }
}

run "role_vocabulary" {
  # ロール語彙もグループ名の一部なので、増減すると API 側の解析対象が変わる
  assert {
    condition     = output.roles == ["owner", "member", "viewer"]
    error_message = "ロール語彙が変わっている。グループ名の末尾に現れる値なので lcn-infra-api も合わせて直すこと"
  }
}
