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
# LC-Cloud OIDC プロバイダ（Keystone フェデレーション）
# ---------------------------------------------------------------------------
# リダイレクト先は provider_lc_cloud.tf でベース URL が変数化されているので、
# staging の DevStack を指せる。パス（Horizon の /auth/callback、Keystone の
# /v3/OS-FEDERATION/protocols/openid/auth）は製品仕様で固定。
#
# **ホスト名は staging/gcp の dns_zone に合わせて書き換えること。**
# DevStack は Horizon と Keystone が同じホストに同居し、Keystone は /identity に
# ぶら下がるので、2つの変数の関係が本番とは少し違う。
lc_cloud_oidc_client_id = "lc-cloud"
lc_cloud_horizon_url    = "http://openstack.staging.lcn.ad.jp"
lc_cloud_keystone_url   = "http://openstack.staging.lcn.ad.jp/identity"

# client_secret は空なら Authentik が生成する。Keystone 側の設定に
# terraform output から渡すこと
# lc_cloud_oidc_client_secret = ""

# ---------------------------------------------------------------------------
# staging では使わないもの
# ---------------------------------------------------------------------------
# いずれも空文字が既定で、空なら該当リソースを作らない。**空のままにする。**
#
#   webhook_secret           入れると staging の Authentik が本番リポジトリへ
#                            repository_dispatch を撃ち、auto-gen-members.yaml を
#                            書き換える Bot が動いてしまう
#   github_oauth_client_id   GitHub/Discord 側に登録されたコールバック URL が
#   discord_oauth_client_id  本番 Authentik を指しているため、staging から
#                            認証を始めても戻ってこられない

# Harbor の OIDC 連携。staging の Harbor を指すなら設定してよい
# harbor_url = "https://harbor.staging.lcn.ad.jp"

# メールは本番と同じサーバーを使う。空のままなら Authentik のグローバル設定
# （コンテナの AUTHENTIK_EMAIL__* = staging/gcp の smtp_* 変数）が使われるので、
# 通常はここを空のままでよい
# smtp_host = ""
