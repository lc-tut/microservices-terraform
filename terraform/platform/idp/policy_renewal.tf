# 年次更新のたびに var.renewal_cycle_year / var.renewal_grad_year を更新して apply する

# Q1/Q2 の表示要否を判定する（renewal 未回答かどうか）
resource "authentik_policy_expression" "needs_renewal" {
  name       = "needs-annual-renewal"
  expression = <<-PYTHON
    CURRENT_CYCLE_YEAR = ${var.renewal_cycle_year}
    return request.user.attributes.get("renewal_year") != CURRENT_CYCLE_YEAR
  PYTHON
}

# Q2（卒業年度コホート向け）を表示するかどうかの判定
resource "authentik_policy_expression" "is_graduating_cohort" {
  name       = "renewal-is-graduating-cohort"
  expression = <<-PYTHON
    CURRENT_GRAD_YEAR = ${var.renewal_grad_year}
    return request.user.attributes.get("grad_year") == CURRENT_GRAD_YEAR
  PYTHON
}

# Q2 で ob-og を選んだ場合のみ本名・連絡先 Stage へ進める判定。
# field_key="attributes.xxx" は prompt_data 上で {"attributes": {"xxx": ...}} という
# ネストした辞書になる（実機で確認済み。フラットな "attributes.xxx" キーではない）
resource "authentik_policy_expression" "chose_ob_og" {
  name       = "renewal-chose-ob-og"
  expression = <<-PYTHON
    attrs = request.context.get("prompt_data", {}).get("attributes", {})
    return attrs.get("renewal_choice") == "ob-og"
  PYTHON
}

# --- authentik_stage_prompt_field に choices 引数が無いため、
#     type = "text" の自由入力 + validation_policies での許容値チェックで代替する ---

resource "authentik_policy_expression" "q1_valid_answer" {
  name       = "renewal-q1-valid-answer"
  expression = <<-PYTHON
    attrs = request.context.get("prompt_data", {}).get("attributes", {})
    answer = attrs.get("renewal_continue", "").strip()
    if answer not in ("continue", "leave"):
      ak_message('「continue」または「leave」のどちらかを入力してください')
      return False
    return True
  PYTHON
}

resource "authentik_policy_expression" "q2_valid_answer" {
  name       = "renewal-q2-valid-answer"
  expression = <<-PYTHON
    attrs = request.context.get("prompt_data", {}).get("attributes", {})
    answer = attrs.get("renewal_choice", "").strip()
    if answer not in ("ob-og", "no-contact", "repeat-year"):
      ak_message('「ob-og」「no-contact」「repeat-year」のいずれかを入力してください')
      return False
    return True
  PYTHON
}
