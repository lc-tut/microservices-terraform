resource "authentik_user" "members" {
  for_each = local.members_by_id

  # username・name は enrollment 後にメンバー自身が変更する → drift を無視
  username  = each.key
  name      = each.key
  email     = local.secrets[each.key].email
  is_active = false

  attributes = jsonencode({
    student_id = local.secrets[each.key].student_id
  })

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [username, name]
  }
}

# ユーザー作成後にリカバリーメールを送信する
# メンバーの大学メールに「アカウントが作成されました。こちらから設定してください」が届く
resource "null_resource" "send_enrollment_email" {
  for_each = local.members_by_id

  triggers = {
    user_pk = authentik_user.members[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      STAGE_UUID=$(curl -sf \
        "${var.authentik_url}/api/v3/stages/email/?name=recovery-email" \
        -H "Authorization: Bearer ${var.authentik_token}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['pk'])")
      curl -sf -X POST \
        "${var.authentik_url}/api/v3/core/users/${self.triggers.user_pk}/recovery_email/?email=true" \
        -H "Authorization: Bearer ${var.authentik_token}" \
        -H "Content-Type: application/json" \
        -d "{\"email_stage\": \"$STAGE_UUID\"}"
    EOT
  }
}
