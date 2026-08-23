locals {
  smtp_configured = var.smtp_host != ""
}

resource "authentik_flow" "recovery" {
  name        = "Password Recovery"
  slug        = "member-recovery"
  title       = "パスワードリセット"
  designation = "recovery"
  layout      = "stacked"
}

# ステージ 1: メールアドレスでユーザーを特定
resource "authentik_stage_identification" "recovery_id" {
  name        = "recovery-identification"
  user_fields = ["email", "username"]
}

# ステージ 2: リセットメール送信
resource "authentik_stage_email" "recovery_email" {
  name                     = "recovery-email"
  activate_user_on_success = true
  token_expiry             = "minutes=30"
  subject                  = "LinuxClub パスワードリセット"
  template                 = "email/password_reset.html"

  # TF_VAR_smtp_host が設定されていれば明示的なSMTP設定を使用する
  use_global_settings = !local.smtp_configured
  host                = local.smtp_configured ? var.smtp_host         : null
  port                = local.smtp_configured ? var.smtp_port         : null
  username            = local.smtp_configured ? var.smtp_username     : null
  password            = local.smtp_configured ? var.smtp_password     : null
  use_tls             = local.smtp_configured ? var.smtp_use_tls      : null
  use_ssl             = local.smtp_configured ? var.smtp_use_ssl      : null
  from_address        = local.smtp_configured ? var.smtp_from_address : null
}

# ステージ 3: ユーザー名選択（仮 ID から自分で決めた名前に変更）
resource "authentik_stage_prompt" "recovery_username" {
  name = "recovery-username-prompt"

  fields = [
    authentik_stage_prompt_field.recovery_username_field.id,
  ]

  validation_policies = [
    authentik_policy_expression.username_rules.id,
  ]
}

resource "authentik_stage_prompt_field" "recovery_username_field" {
  name        = "recovery-field-username"
  field_key   = "username"
  label       = "ユーザー名（英小文字・数字・ハイフン、3〜31文字）"
  type        = "text"
  required    = true
  placeholder = "例: taro-yamada"
  sub_text    = "このユーザー名は LC-Cloud・GitHub 連携などで使用されます。変更すると各サービスとの連携が壊れる可能性があるため、慎重に選んでください。"
  order       = 100
}

resource "authentik_flow_stage_binding" "recovery_username" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_prompt.recovery_username.id
  order  = 25
}

# ステージ 4: 新パスワード入力
resource "authentik_stage_prompt" "recovery_password" {
  name = "recovery-password-prompt"

  fields = [
    authentik_stage_prompt_field.recovery_password_new.id,
    authentik_stage_prompt_field.recovery_password_repeat.id,
  ]
}

resource "authentik_stage_prompt_field" "recovery_password_new" {
  name      = "recovery-field-password-new"
  field_key = "password"
  label     = "新しいパスワード"
  type      = "password"
  required  = true
  order     = 100
}

resource "authentik_stage_prompt_field" "recovery_password_repeat" {
  name      = "recovery-field-password-repeat"
  field_key = "password_repeat"
  label     = "新しいパスワード（確認）"
  type      = "password"
  required  = true
  order     = 200
}

# ステージ 4: パスワード保存
resource "authentik_stage_user_write" "recovery_write" {
  name               = "recovery-user-write"
  user_creation_mode = "never_create"
}

resource "authentik_flow_stage_binding" "recovery_id" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_identification.recovery_id.id
  order  = 10
}

resource "authentik_flow_stage_binding" "recovery_email" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_email.recovery_email.id
  order  = 20
}

resource "authentik_flow_stage_binding" "recovery_password" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_prompt.recovery_password.id
  order  = 35
}

resource "authentik_flow_stage_binding" "recovery_write" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_user_write.recovery_write.id
  order  = 40
}
