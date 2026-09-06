output "roles" {
  value       = ["owner", "member", "viewer"]
  description = "全スコープ共通のロール語彙。写像表（keystone_role 等）のキー"
}

output "scope_roles" {
  value       = var.scope_type == "user" ? ["owner"] : ["owner", "member", "viewer"]
  description = <<-EOT
    そのスコープで実際に作るロール。グループを for_each で作るときはこちらを使う。
    個人 project は本人だけが入るため owner のみで、roles をそのまま回すと
    永久に空の user-<id>-member / user-<id>-viewer が残る。
  EOT
}

output "grants" {
  value = [
    "billing-view",
    "billing-request",
    "harbor-admin",
    "k8s-exec",
    "secret-admin",
  ]
  description = <<-EOT
    ロールとは独立に個人へ付与できるアドオン権限の語彙（18-access-control.md「軸 1」）。
    ここに無い値を members.yaml の grants に書くと catalog 側の precondition で弾かれる。
    語彙の追加は modules/ への PR＝ circle-admin 承認が必要。
  EOT
}

output "group_names" {
  # 注意: この命名規則は lcn-infra-api との契約になっている。
  # 同 API は X-authentik-groups に入ってくる "team-web-member" という文字列を
  # 分解して「web チームの member」と判定しており、判断材料はこれしかない。
  # prefix・区切り文字・並び順を変えると Terraform 側は何も壊れないまま
  # API の認可だけが黙って壊れる。変更するときは lcn-infra-api も同時に直すこと。
  value = {
    for r in ["owner", "member", "viewer"] :
    r => "${local.prefix}-${var.scope_name}-${r}"
  }
  description = <<-EOT
    Authentik / Keystone で共通に使うグループ名（例: team-infra-owner）。
    Keystone federation mapping はこの名前で Authentik のグループクレームを写す。
    lcn-infra-api もこの名前を解析して所属とロールを導出する（上記コメント参照）。
  EOT
}

output "keystone_role" {
  value       = local.keystone
  description = "抽象ロール → Keystone ロール名。project スコープでは使わない（Keystone project はチーム単位のため）"
}

output "harbor_role" {
  value       = local.harbor
  description = "抽象ロール → Harbor のプロジェクトメンバーロール名"
}

output "k8s_role" {
  value       = local.k8s
  description = "抽象ロール → Kubernetes 組み込み ClusterRole 名"
}

output "github_team" {
  value       = local.github_team
  description = "抽象ロール → GitHub Team 名。project スコープと viewer は null（Team を割り当てない）"
}
