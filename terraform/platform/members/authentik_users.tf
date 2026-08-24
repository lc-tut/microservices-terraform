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

# ユーザー作成後にリカバリーメールを送信する（active のみ。ob-og は設定済みのため対象外）
resource "null_resource" "send_enrollment_email" {
  for_each = { for id, m in local.members_by_id : id => m if m.status == "active" }

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
