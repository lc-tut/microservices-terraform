resource "authentik_flow" "enrollment" {
  name        = "Member Enrollment"
  slug        = "member-enrollment"
  title       = "LinuxClub メンバー登録"
  designation = "enrollment"
  layout      = "stacked"
}

resource "authentik_stage_invitation" "verify" {
  name                             = "enrollment-invitation-verify"
  continue_flow_without_invitation = false
}

resource "authentik_stage_prompt" "user_info" {
  name = "enrollment-user-info"

  fields = [
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.display_name.id,
    authentik_stage_prompt_field.password.id,
    authentik_stage_prompt_field.password_repeat.id,
  ]

  validation_policies = [
    authentik_policy_expression.username_rules.id,
  ]
}

resource "authentik_stage_prompt_field" "username" {
  name        = "enrollment-field-username"
  field_key   = "username"
  label       = "ユーザー名（LC-Cloud ID）"
  type        = "text"
  placeholder = "例: alice（半角英小文字・数字・ハイフン）"
  required    = true
  order       = 100
}

resource "authentik_stage_prompt_field" "display_name" {
  name        = "enrollment-field-display-name"
  field_key   = "name"
  label       = "表示名"
  type        = "text"
  placeholder = "例: Alice Yamada"
  required    = true
  order       = 200
}

resource "authentik_stage_prompt_field" "password" {
  name      = "enrollment-field-password"
  field_key = "password"
  label     = "パスワード"
  type      = "password"
  required  = true
  order     = 300
}

resource "authentik_stage_prompt_field" "password_repeat" {
  name      = "enrollment-field-password-repeat"
  field_key = "password_repeat"
  label     = "パスワード（確認）"
  type      = "password"
  required  = true
  order     = 400
}

resource "authentik_stage_user_write" "write" {
  name                     = "enrollment-user-write"
  user_creation_mode       = "always_create"
  create_users_as_inactive = false
  create_users_group       = authentik_group.all_members.id
}

resource "authentik_stage_user_login" "login" {
  name = "enrollment-user-login"
}

resource "authentik_flow_stage_binding" "verify" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_invitation.verify.id
  order  = 10
}

resource "authentik_flow_stage_binding" "user_info" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_prompt.user_info.id
  order  = 20
}

resource "authentik_flow_stage_binding" "write" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_user_write.write.id
  order  = 30
}

resource "authentik_flow_stage_binding" "login" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_user_login.login.id
  order  = 40
}

# ---- Stage 5: GitHub/Discord連携の推奨案内 ----
# authentik_stage_source は Enterprise 限定のため、静的な案内 Stage で代替

resource "authentik_stage_prompt_field" "recommend_connect" {
  name      = "enrollment-field-recommend-connect"
  field_key = "recommend_connect_info"
  label     = "GitHub・Discord連携のご案内"
  type      = "static"
  sub_text  = <<-TEXT
    GitHub・Discord アカウントの連携は任意ですが、連携しておくと
    Organization への招待や OB/OG 向け Discord ロールの自動付与がスムーズになります。
    後からいつでも「Connected Sources」画面（ユーザー設定）から連携できます。
  TEXT
  order     = 100
}

resource "authentik_stage_prompt" "recommend_connect" {
  name   = "enrollment-recommend-connect"
  fields = [authentik_stage_prompt_field.recommend_connect.id]
}

resource "authentik_flow_stage_binding" "recommend_connect" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_prompt.recommend_connect.id
  order  = 50
}
