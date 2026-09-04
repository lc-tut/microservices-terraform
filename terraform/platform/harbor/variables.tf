variable "harbor_url" {
  type        = string
  description = "terraform/platform/infra/harbor-infra/ の `terraform output -raw harbor_url` の値"
}

variable "harbor_admin_password" {
  type        = string
  description = "terraform/platform/infra/harbor-infra/ の `terraform output -raw harbor_admin_password` の値"
  sensitive   = true
}

# ---- OIDC（Authentik 連携） ----
# 値はいずれも terraform/platform/idp/ の apply 後、対応する output から渡す
# （harbor_oidc_client_id / harbor_oidc_client_secret / harbor_oidc_issuer）。

variable "oidc_name" {
  type        = string
  description = "Harbor のログイン画面に表示される OIDC プロバイダ名"
  default     = "authentik"
}

variable "oidc_endpoint" {
  type        = string
  description = "terraform/platform/idp/ の harbor_oidc_issuer 出力（Authentik 側 Application の issuer URL）"
}

variable "oidc_client_id" {
  type        = string
  description = "terraform/platform/idp/ の harbor_oidc_client_id 出力（固定値 \"harbor\"）"
  default     = "harbor"
}

variable "oidc_client_secret" {
  type        = string
  description = "terraform/platform/idp/ の harbor_oidc_client_secret 出力"
  sensitive   = true
}

variable "oidc_verify_cert" {
  type        = bool
  description = "Authentik が TLS 未設定（HTTP 直公開、Phase 9 まで）の間は false にする"
  default     = false
}

variable "oidc_auto_onboard" {
  type        = bool
  description = "true にするとユーザーの初回ログイン時の onboarding 画面（username 選択）をスキップし oidc_user_claim の値をそのまま使う"
  default     = true
}

variable "oidc_user_claim" {
  type        = string
  description = "Harbor のユーザー名に使う ID Token のクレーム名。Authentik の scope-profile マッピングが preferred_username を出す"
  default     = "preferred_username"
}

variable "primary_auth_mode" {
  type        = bool
  description = "OIDC をプライマリのログイン手段にするか（admin は引き続き DB 認証でログイン可能）"
  default     = true
}
