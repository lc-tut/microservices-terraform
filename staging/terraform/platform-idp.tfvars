# terraform/platform/idp を staging に向けて apply するときの変数。
#   staging/terraform/tf.sh platform/idp plan
#
# authentik_url / authentik_token は tf.sh が staging/gcp の output から
# 環境変数で渡すので、ここには書かない。

# Middleware API（lcn-infra-api / lcn-billing-api）用の OIDC プロバイダ。
# staging/gcp の oidc_client_id と同じ値にすること。
# application slug にもなり、issuer の一部（/application/o/<slug>/）になる
middleware_oidc_client_id = "lcn-api"

# SPA と CLI のコールバック URL。
# **ホスト名は staging/gcp の dns_zone に合わせて書き換えること。**
middleware_oidc_redirect_uris = [
  # "https://console.staging.lcn.ad.jp/oauth/callback",
  # CLI のループバック受け口（開発中に token を取るのに使う）
  "http://localhost:8888/callback",
  "http://127.0.0.1:8888/callback",
]

# Harbor の OIDC 連携。staging/gcp が Harbor を建てている場合に設定する
# harbor_url = "https://harbor.staging.lcn.ad.jp"

# メールは本番と同じサーバーを使う。空のままなら Authentik の
# グローバル設定（コンテナの AUTHENTIK_EMAIL__* = staging/gcp の smtp_* 変数）が
# 使われるので、通常はここを空のままでよい
# smtp_host = ""
