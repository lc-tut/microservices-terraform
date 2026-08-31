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

# pending_user が既にセット済み（recovery_email API で発行されたリンク経由）なら
# identification をスキップする。自分で「パスワードを忘れた」から入った場合は
# pending_user が無いのでこれまで通り表示される
# （実ソース authentik/core/api/users.py の _create_recovery_link で
# PLAN_CONTEXT_PENDING_USER が渡されることを確認済み）
resource "authentik_policy_expression" "skip_identification_if_pending_user" {
  name       = "recovery-skip-identification-if-pending-user"
  expression = <<-PYTHON
    return not request.context.get("pending_user")
  PYTHON
}

# 初回アカウント設定が済んでいなければ「ようこそ」案内を先頭に出す。
# 独自の attributes フラグではなく Django 標準の has_usable_password() を使う。
# attributes は terraform/platform/members/ 側が丸ごと jsonencode で上書き管理
# しているため、カスタムフラグを attributes に置くと members スタックを
# 再apply するたびに消えてしまう（実機検証で確認済み・2026-08-25）。
# has_usable_password() は User モデル本体のパスワードフィールドを見るだけで
# Terraform の管理対象と一切重ならないため、この問題が起きない
resource "authentik_policy_expression" "needs_welcome_intro" {
  name       = "recovery-needs-welcome-intro"
  expression = <<-PYTHON
    return not request.user.has_usable_password()
  PYTHON
}

# ステージ 0: ようこそ案内（初回のみ）
resource "authentik_stage_prompt_field" "welcome_intro" {
  name      = "recovery-field-welcome-intro"
  field_key = "welcome_intro_info"
  label     = "LinuxClubへようこそ！"
  type      = "static"
  sub_text  = "サークルへの登録が完了しました。続けてユーザー名とパスワードを設定してください。"
  order     = 100

  # static 型フィールドは placeholder が送信値のデフォルトになる（画面上の
  # プレースホルダーとしては使われない）。空文字のままだと送信時に
  # "This field may not be blank." で弾かれるため、非空の値を入れておく
  placeholder = "ok"
}

resource "authentik_stage_prompt" "welcome_intro" {
  name   = "recovery-welcome-intro"
  fields = [authentik_stage_prompt_field.welcome_intro.id]
}

resource "authentik_flow_stage_binding" "welcome_intro" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_prompt.welcome_intro.id
  order  = 5
}

resource "authentik_policy_binding" "welcome_intro_gate" {
  target = authentik_flow_stage_binding.welcome_intro.id
  policy = authentik_policy_expression.needs_welcome_intro.id
  order  = 0
}

# ステージ 1: メールアドレスでユーザーを特定（pending_user 有りならスキップ）
resource "authentik_stage_identification" "recovery_id" {
  name        = "recovery-identification"
  user_fields = ["email", "username"]
}

resource "authentik_flow_stage_binding" "recovery_id" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_identification.recovery_id.id
  order  = 10
}

resource "authentik_policy_binding" "recovery_id_gate" {
  target = authentik_flow_stage_binding.recovery_id.id
  policy = authentik_policy_expression.skip_identification_if_pending_user.id
  order  = 0
}

# ステージ 2: リセットメール送信（自己申告の「パスワードを忘れた」用）
resource "authentik_stage_email" "recovery_email" {
  name                     = "recovery-email"
  activate_user_on_success = true
  token_expiry             = "minutes=30"
  subject                  = "LinuxClub パスワードリセット"
  template                 = "email/password_reset.html"

  # TF_VAR_smtp_host が設定されていれば明示的なSMTP設定を使用する
  use_global_settings = !local.smtp_configured
  host                = local.smtp_configured ? var.smtp_host : null
  port                = local.smtp_configured ? var.smtp_port : null
  username            = local.smtp_configured ? var.smtp_username : null
  password            = local.smtp_configured ? var.smtp_password : null
  use_tls             = local.smtp_configured ? var.smtp_use_tls : null
  use_ssl             = local.smtp_configured ? var.smtp_use_ssl : null
  from_address        = local.smtp_configured ? var.smtp_from_address : null
}

resource "authentik_flow_stage_binding" "recovery_email" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_email.recovery_email.id
  order  = 20
}

# 初回アカウント設定用の「ようこそ」メール文面。
# member-recovery Flow には bind しない（内容だけ使う）。
# authentik_users.tf の send_enrollment_email がこちらの名前で参照し、
# recovery_email API の email_stage パラメータへ渡す
resource "authentik_stage_email" "welcome_email" {
  name                     = "welcome-email"
  activate_user_on_success = true
  token_expiry             = "minutes=30"
  subject                  = "LinuxClubへようこそ！アカウント設定のお願い"
  template                 = "email/account_confirmation.html"

  use_global_settings = !local.smtp_configured
  host                = local.smtp_configured ? var.smtp_host : null
  port                = local.smtp_configured ? var.smtp_port : null
  username            = local.smtp_configured ? var.smtp_username : null
  password            = local.smtp_configured ? var.smtp_password : null
  use_tls             = local.smtp_configured ? var.smtp_use_tls : null
  use_ssl             = local.smtp_configured ? var.smtp_use_ssl : null
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

# このステージ（recovery_write）でパスワードが実際に保存されると
# has_usable_password() が True になり、以降は needs_welcome_intro が
# 自動的に False になる（＝次回からは本当のパスワードリセット扱い）。
# 実機検証済み（2026-08-25）。ただし authentik の FlowPlan は user+flow 単位で
# 既定 300 秒キャッシュされる（cache.timeout_flows）ため、同一ユーザーが
# アカウント設定直後の数分以内にもう一度リンクを踏むと、古いキャッシュにより
# 「ようこそ」案内が一度だけ再表示されることがある。実害は軽微（無害な追加
# 画面が一枚出るだけ）なので許容している
resource "authentik_flow_stage_binding" "recovery_password" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_prompt.recovery_password.id
  order  = 35
}

# ステージ 5: パスワード保存
resource "authentik_stage_user_write" "recovery_write" {
  name               = "recovery-user-write"
  user_creation_mode = "never_create"
}

resource "authentik_flow_stage_binding" "recovery_write" {
  target = authentik_flow.recovery.uuid
  stage  = authentik_stage_user_write.recovery_write.id
  order  = 40
}
