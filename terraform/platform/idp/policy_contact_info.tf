resource "authentik_policy_expression" "personal_email_not_university" {
  name       = "contact-info-reject-university-domain"
  expression = <<-PYTHON
    email = request.context.get("prompt_data", {}).get("attributes", {}).get("personal_email", "")
    if email.lower().endswith("@edu.teu.ac.jp"):
      ak_message("大学のメールアドレスではなく、卒業後も使える個人のメールアドレスを入力してください")
      return False
    return True
  PYTHON
}

resource "authentik_policy_expression" "phone_format" {
  name       = "contact-info-phone-format"
  expression = <<-PYTHON
    import re
    phone = request.context.get("prompt_data", {}).get("attributes", {}).get("phone", "")
    if not phone:
      return True  # 任意フィールドなので未入力は許可

    digits = phone.replace("-", "").replace(" ", "")
    if digits.startswith("+"):
      if not re.fullmatch(r"\+[1-9]\d{7,14}", digits):
        ak_message("海外の電話番号は + と国番号から入力してください（例: +81901234567）")
        return False
    else:
      if not re.fullmatch(r"0\d{9,10}", digits):
        ak_message("電話番号は日本国内形式（0X0-XXXX-XXXX）か、+81 のような国際形式で入力してください")
        return False
    return True
  PYTHON
}
