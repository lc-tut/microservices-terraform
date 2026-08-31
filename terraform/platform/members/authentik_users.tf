# all-members / ob-og は terraform/platform/idp/ 側の別スタックが所有するため data source で参照
data "authentik_group" "all_members" {
  name = "all-members"
}

data "authentik_group" "ob_og" {
  name = "ob-og"
}

resource "authentik_user" "members" {
  for_each = local.members_by_id

  # username・name は enrollment 後にメンバー自身が変更する → drift を無視
  username = each.key
  name     = each.key
  email    = local.secrets[each.key].email

  # active は既存通り false のまま維持（is_active の既存挙動には手を入れない）。
  # alumni は連絡不要という意思表示のため false
  is_active = each.value.status == "ob-og" ? true : false

  groups = (
    each.value.status == "ob-og" ? [data.authentik_group.ob_og.id] :
    each.value.status == "alumni" ? [] :
    [data.authentik_group.all_members.id]
  )

  attributes = jsonencode({
    student_id = local.secrets[each.key].student_id
    lcn_id     = each.key             # email 書き換え後も辿れる不変の識別子
    grad_year  = each.value.grad_year # フォルダ移動のたびに再計算される
  })

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [username, name]
  }
}

# ユーザー作成後にウェルカムメールを送信する（active のみ。ob-og は設定済みのため対象外）。
# recovery.tf の welcome-email（member-recovery Flow には bind していない、文面だけ使う
# EmailStage）を参照する。届いたリンクの遷移先自体は member-recovery Flow のまま
# （recovery_email API が brand.flow_recovery に固定されているため）だが、
# pending_user 済みなら identification をスキップし、has_usable_password()
# が False（＝まだ一度もパスワードを設定していない）なら「ようこそ」案内を
# 先頭に出す Stage 分岐で初回設定らしい体験にしている。
#
# Accept-Language: ja が必須。User.locale() は request.LANGUAGE_CODE がある場合
# 常にそれを最優先する（authentik/core/models.py）ため、ヘッダー無しだと
# settings.LANGUAGE_CODE の既定値 "en-us" になり英語メールが送られてしまう
# （ユーザー個別の locale 属性やブランドの locale 設定は無視される）。
# 実機検証済み（2026-08-25）: ja_JP 翻訳カタログは同梱されており、
# このヘッダーだけで件名・本文とも日本語化されることを確認済み
resource "null_resource" "send_enrollment_email" {
  for_each = { for id, m in local.members_by_id : id => m if m.status == "active" }

  triggers = {
    user_pk = authentik_user.members[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      STAGE_UUID=$(curl -sf \
        "${var.authentik_url}/api/v3/stages/email/?name=welcome-email" \
        -H "Authorization: Bearer ${var.authentik_token}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['pk'])")
      curl -sf -X POST \
        "${var.authentik_url}/api/v3/core/users/${self.triggers.user_pk}/recovery_email/?email=true" \
        -H "Authorization: Bearer ${var.authentik_token}" \
        -H "Content-Type: application/json" \
        -H "Accept-Language: ja" \
        -d "{\"email_stage\": \"$STAGE_UUID\"}"
    EOT
  }
}
