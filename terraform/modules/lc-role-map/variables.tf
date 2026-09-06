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
}
