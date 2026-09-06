# 抽象ロール → 各システムのネイティブロールへの写像表。
# この写像はリポジトリ全体でここ 1 箇所にだけ存在させる（18-access-control.md）。
# 新しい消費者（Harbor・K8s 等）を実装するときも、写像を各所にコピーせず
# このモジュールに output を足して参照すること。

locals {
  prefix = var.scope_type == "team" ? "team" : "proj"

  # Keystone の既定ロールは admin / member / reader の 3 つしかないため、
  # owner と member は OpenStack API 上まったく同じ権限になる。
  # owner の特別さは GitHub の承認権・Harbor・K8s・yaml の編集権で表現する
  # （18-access-control.md「この写像が『漏れる』ところ」参照）。
  keystone = {
    owner  = "member"
    member = "member"
    viewer = "reader"
  }

  harbor = {
    owner  = "projectadmin"
    member = "developer"
    viewer = "guest"
  }

  # Kubernetes の組み込み ClusterRole 名（RoleBinding で namespace に束ねる）
  k8s = {
    owner  = "admin"
    member = "edit"
    viewer = "view"
  }

  # GitHub Team は team スコープにのみ存在する。
  # viewer は Org メンバーである時点でリポジトリを read できるため Team を割り当てない。
  github_team = var.scope_type == "team" ? {
    owner  = "${var.scope_name}-lead"
    member = var.scope_name
    viewer = null
    } : {
    owner  = null
    member = null
    viewer = null
  }
}
