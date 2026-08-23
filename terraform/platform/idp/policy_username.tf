resource "authentik_policy_expression" "username_rules" {
  name       = "enrollment-username-rules"
  expression = <<-PYTHON
    import re
    username = request.context.get("prompt_data", {}).get("username", "")
    if not re.fullmatch(r"[a-z][a-z0-9\-]{2,30}", username):
      ak_message("ユーザー名は半角英小文字で始まり、英小文字・数字・ハイフンのみ使用可（3〜31文字）")
      return False
    from authentik.core.models import User
    if User.objects.filter(username=username).exists():
      ak_message("このユーザー名はすでに使われています")
      return False
    return True
  PYTHON
}
