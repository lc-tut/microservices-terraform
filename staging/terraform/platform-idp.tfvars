# terraform/platform/idp を staging に向けて apply するときの変数。
#   staging/terraform/tf.sh platform/idp plan
#
# authentik_url / authentik_token は tf.sh が staging/gcp の output から
# 環境変数で渡すので、ここには書かない。

# ---------------------------------------------------------------------------
# そのまま入るもの（何も指定しなくてよい）
# ---------------------------------------------------------------------------
# ブランド（ロゴ・favicon・flow 背景）・全 Flow（enrollment / recovery /
# annual_renewal / authentication）・ポリシー・グループは、変数に依存しない
# ただの Authentik リソースなので staging にもそのまま入る。
#
# ブランド画像は assets/ を raw.githubusercontent.com 経由で参照している
# （brand.tf）。参照先が main に固定されているので、**画像を差し替えたときは
# main に push するまで staging にも反映されない**（未 push だと 404 になる）。
# staging の Authentik から raw.githubusercontent.com へ出られる必要があるが、
# platform VM は外部 IP を持つので届く。

# ---------------------------------------------------------------------------
# Middleware API（lcn-infra-api / lcn-billing-api）用の OIDC プロバイダ
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# **本番の値を入れてはいけないもの**
# ---------------------------------------------------------------------------
# 以下はすべて空文字が既定で、空なら該当リソースを作らない。
# staging では空のままにしておくのが安全側。

# GitHub / Discord の OAuth Source。
# **本番と同じ client_id を入れると壊れる。** GitHub/Discord 側に登録されている
# コールバック URL は本番 Authentik のホストを指しているので、staging から
# 認証を始めても戻ってこられない。staging で試すなら OAuth App を別に作り、
# コールバックを https://auth.<staging zone>/source/oauth/callback/<slug>/ で登録すること。
# github_oauth_client_id  = ""
# discord_oauth_client_id = ""

# 通知 Webhook。
# **入れると staging の Authentik が本番リポジトリに repository_dispatch を撃つ。**
# enrollment 完了で auto-gen-members.yaml を書き換える Bot が動いてしまうので、
# staging では空のままにすること。試すならフォークを github_repo_owner に指定する。
# webhook_secret = ""

# LC-Cloud OIDC プロバイダ（Keystone フェデレーション）。
# **staging では使えない。** provider_lc_cloud.tf のリダイレクト URI が
# horizon.lc-cloud.example.internal / keystone.lc-cloud.example.internal に
# 直書きされていて変数化されていないため、staging の DevStack を指せない。
# staging で Keystone フェデレーションを試すなら、まず provider_lc_cloud.tf の
# URI を変数にする必要がある。
# lc_cloud_oidc_client_id = ""

# Harbor の OIDC 連携。staging の Harbor を指すなら設定してよい
# harbor_url = "https://harbor.staging.lcn.ad.jp"

# メールは本番と同じサーバーを使う。空のままなら Authentik のグローバル設定
# （コンテナの AUTHENTIK_EMAIL__* = staging/gcp の smtp_* 変数）が使われるので、
# 通常はここを空のままでよい
# smtp_host = ""
