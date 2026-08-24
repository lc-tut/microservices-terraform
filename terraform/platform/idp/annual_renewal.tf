# field_key="attributes.xxx" による user_write への書き込み、および
# 各 Stage の policy binding によるスキップ制御はローカル実機で動作確認済み
# （documents/authentik/forms/02-annual-renewal.md 参照）。
# ⚠️ 未検証: designation=stage_configuration をログイン中に自動で割り込ませる配線方法

resource "authentik_flow" "annual_renewal" {
  name        = "Annual Renewal"
  slug        = "annual-renewal"
  title       = "継続確認"
  designation = "stage_configuration"
  layout      = "stacked"
  background  = "${local.idp_assets_base_url}/linuxclub_flow_background.jpg"
}

# ---- Stage 1: Q1（全員向け継続確認） ----

resource "authentik_stage_prompt_field" "continue_next_year" {
  name      = "renewal-field-continue-next-year"
  field_key = "attributes.renewal_continue"
  label     = "来年度も活動を継続しますか？"
  type      = "radio-button-group"
  required  = true
  order     = 100

  # radio-button-group/dropdown は choices という専用引数を持たず、
  # placeholder を Python 式として評価した戻り値（リスト）が選択肢になる
  # （authentik/stages/prompt/models.py の get_choices 実装で確認済み）
  placeholder_expression = true
  placeholder            = <<-PYTHON
    return [
      {"value": "continue", "label": "継続する"},
      {"value": "leave", "label": "継続しない"},
    ]
  PYTHON
}

# renewal.year のスタンプ用。ユーザーには見えない
resource "authentik_stage_prompt_field" "renewal_year_stamp" {
  name                     = "renewal-field-year-stamp"
  field_key                = "attributes.renewal_year"
  label                    = "renewal_year（内部用）"
  type                     = "hidden"
  initial_value            = tostring(var.renewal_cycle_year)
  initial_value_expression = false
  order                    = 900
}

resource "authentik_stage_prompt" "q1" {
  name = "renewal-q1"
  fields = [
    authentik_stage_prompt_field.continue_next_year.id,
    authentik_stage_prompt_field.renewal_year_stamp.id,
  ]
  validation_policies = [authentik_policy_expression.q1_valid_answer.id]
}

resource "authentik_flow_stage_binding" "renewal_q1" {
  target = authentik_flow.annual_renewal.uuid
  stage  = authentik_stage_prompt.q1.id
  order  = 10
}

# ---- Stage 2: Q2（卒業年度コホートのみ表示） ----

resource "authentik_stage_prompt_field" "graduation_choice" {
  name      = "renewal-field-graduation-choice"
  field_key = "attributes.renewal_choice"
  label     = "今年度で卒業しますか？"
  type      = "radio-button-group"
  sub_text  = "卒業しない場合は「留年する」を選んでください。来年度以降のコホートへ移動します。"
  required  = true
  order     = 100

  placeholder_expression = true
  placeholder            = <<-PYTHON
    return [
      {"value": "ob-og", "label": "卒業してOB/OGとして関わる"},
      {"value": "no-contact", "label": "卒業して連絡は不要"},
      {"value": "repeat-year", "label": "留年する（卒業しない）"},
    ]
  PYTHON
}

resource "authentik_stage_prompt" "q2" {
  name                = "renewal-q2"
  fields              = [authentik_stage_prompt_field.graduation_choice.id]
  validation_policies = [authentik_policy_expression.q2_valid_answer.id]
}

resource "authentik_flow_stage_binding" "renewal_q2" {
  target = authentik_flow.annual_renewal.uuid
  stage  = authentik_stage_prompt.q2.id
  order  = 20
}

resource "authentik_policy_binding" "renewal_q2_gate" {
  target = authentik_flow_stage_binding.renewal_q2.id
  policy = authentik_policy_expression.is_graduating_cohort.id
  order  = 0
}

# ---- Stage 3: 本名・連絡先（Q2 で ob-og を選んだ場合のみ） ----
# documents/authentik/forms/03-contact-info.md の「文脈B」に対応

resource "authentik_stage_prompt_field" "real_name_required" {
  name      = "contact-info-field-real-name"
  field_key = "attributes.real_name"
  label     = "本名"
  type      = "text"
  required  = true
  order     = 100
}

resource "authentik_stage_prompt_field" "personal_email_required" {
  name      = "contact-info-field-personal-email"
  field_key = "attributes.personal_email"
  label     = "個人メールアドレス（大学メール以外）"
  type      = "email"
  required  = true
  order     = 200
}

resource "authentik_stage_prompt_field" "phone_optional" {
  name      = "contact-info-field-phone"
  field_key = "attributes.phone"
  label     = "電話番号（任意）"
  type      = "text"
  required  = false
  order     = 300
}

resource "authentik_stage_prompt" "contact_info_required" {
  name = "contact-info-required"
  fields = [
    authentik_stage_prompt_field.real_name_required.id,
    authentik_stage_prompt_field.personal_email_required.id,
    authentik_stage_prompt_field.phone_optional.id,
  ]
  validation_policies = [
    authentik_policy_expression.personal_email_not_university.id,
    authentik_policy_expression.phone_format.id,
  ]
}

resource "authentik_flow_stage_binding" "renewal_contact_info" {
  target = authentik_flow.annual_renewal.uuid
  stage  = authentik_stage_prompt.contact_info_required.id
  order  = 30

  # chose_ob_og は直前の Stage 2（Q2）の回答を見るため、プラン構築時点（Q2 未回答）の
  # 一発評価では常に False になり Stage が外れてしまう。evaluate_on_plan=false で
  # 初期プランには無条件で含め、re_evaluate_policies=true で Q2 回答後に再評価する
  # （実機のソースコード（authentik/flows/planner.py, markers.py）で確認済み）
  evaluate_on_plan     = false
  re_evaluate_policies = true
}

resource "authentik_policy_binding" "renewal_contact_info_gate" {
  target = authentik_flow_stage_binding.renewal_contact_info.id
  policy = authentik_policy_expression.chose_ob_og.id
  order  = 0
}

# ---- Stage 4: 回答を user attribute に書き込む ----

resource "authentik_stage_user_write" "renewal_record" {
  name               = "renewal-record"
  user_creation_mode = "never_create" # 既存ユーザーの更新のみ。新規作成しない
}

resource "authentik_flow_stage_binding" "renewal_record" {
  target = authentik_flow.annual_renewal.uuid
  stage  = authentik_stage_user_write.renewal_record.id
  order  = 40
}
