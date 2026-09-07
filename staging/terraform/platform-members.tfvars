# terraform/platform/members を staging に向けて apply するときの変数。
#   staging/terraform/tf.sh platform/members plan

# **本物のメールを本物の宛先に送らないための最重要設定。**
# 台帳（members_secrets.yaml）に入っているのは本物のメールアドレスで、
# staging の Authentik は本番と同じメールサーバーを使う。true のまま apply すると
# 全 active メンバーに本物の招待メールが届く。
send_enrollment_email = false
