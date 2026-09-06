variable "scope_type" {
  type        = string
  description = "権限スコープの種類。team か project（18-access-control.md「スコープと継承」参照）"

  validation {
    condition     = contains(["team", "project"], var.scope_type)
    error_message = "scope_type は team または project を指定してください。"
  }
}

variable "scope_name" {
  type        = string
  description = "チーム名またはプロジェクト名。グループ名の一部になる"

  validation {
    # Authentik / Keystone / Harbor / GitHub のすべてで安全に使える文字種に限定する。
    # 先頭・末尾はハイフン不可（GitHub Team の slug 化で潰れるため）。
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.scope_name))
    error_message = "scope_name は英小文字・数字・ハイフンのみ（先頭末尾はハイフン不可）で指定してください。"
  }

  validation {
    # グループ名は "<prefix>-<scope_name>-<role>" で組み立てるため、
    # scope_name がロール名で終わると "team-foo-owner-member" のような
    # 紛らわしい名前になる。末尾のハイフンで分割すれば一意に解釈できるので
    # 完全な衝突は起きないが、lcn-infra-api 側が素朴に分割した場合に
    # 誤判定しうる。実際のチーム名は web / infra なので実害はなく、
    # 名前空間を素直に保つための予防措置。
    condition     = !can(regex("-(owner|member|viewer)$", var.scope_name))
    error_message = "scope_name の末尾に -owner / -member / -viewer は使えません（グループ名のロール部分と紛らわしいため）。"
  }
}
