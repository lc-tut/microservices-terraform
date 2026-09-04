# terraform/platform/harbor

Harbor 本体（`terraform/platform/infra/harbor-infra/` が構築した VM）に対して、
Harbor API 経由でアプリケーションレベルの設定を行う root。
`terraform/platform/openstack/cloudkitty/`（CloudKitty API に Hashmap ルールを設定）や
`terraform/platform/idp/`（Authentik API にアプリケーション設定を行う）と同じ立ち位置で、
VM のプロビジョニング（`infra/harbor-infra/`）とは分離している。

現時点では OIDC（Authentik）連携の設定（`harbor_config_auth`）のみ。

## 前提

1. `terraform/platform/infra/harbor-infra/` が apply 済みであること。
2. `terraform/platform/idp/` に `var.harbor_url`（1. の `terraform output -raw harbor_url`）
   を渡して apply 済みであること（Authentik 側に Harbor 用 OAuth2 Provider +
   Application が作られ、`harbor_oidc_client_id` / `harbor_oidc_client_secret` /
   `harbor_oidc_issuer` が出力される）。

## デプロイ

```bash
export OS_CLIENT_CONFIG_FILE="$(git rev-parse --show-toplevel)/local/clouds.yaml"  # 直接使わないが統一のため
export AWS_ENDPOINT_URL_S3=http://localhost:19000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1

# 1. harbor-infra の出力を取得
cd ../infra/harbor-infra
HARBOR_URL=$(terraform output -raw harbor_url)
HARBOR_ADMIN_PASSWORD=$(terraform output -raw harbor_admin_password)

# 2. idp/ に harbor_url を渡して apply（Authentik 側に Provider/Application を作る）
cd ../../idp
terraform apply -var="harbor_url=${HARBOR_URL}"  # authentik_url/authentik_token 等は既存の運用どおり
OIDC_CLIENT_ID=$(terraform output -raw harbor_oidc_client_id)
OIDC_CLIENT_SECRET=$(terraform output -raw harbor_oidc_client_secret)
OIDC_ISSUER=$(terraform output -raw harbor_oidc_issuer)

# 3. この root を apply
cd ../harbor
terraform init && terraform apply \
  -var="harbor_url=${HARBOR_URL}" \
  -var="harbor_admin_password=${HARBOR_ADMIN_PASSWORD}" \
  -var="oidc_endpoint=${OIDC_ISSUER}" \
  -var="oidc_client_id=${OIDC_CLIENT_ID}" \
  -var="oidc_client_secret=${OIDC_CLIENT_SECRET}"
```

> **本番 Ceph RGW backend への適用時の注意**: `infra/harbor-infra/`・`idp/` と同じく、
> この root もローカル state（`backend_override.tf`）で実機に適用する想定。
> 本番 backend の state はまだ空のまま。

## 動作確認

```bash
curl -fsS "${HARBOR_URL}/api/v2.0/systeminfo" | python3 -m json.tool
# auth_mode が "oidc_auth" になっていること
```

ブラウザで `${HARBOR_URL}` を開くと「LOGIN VIA OIDC PROVIDER」ボタンが表示される。
admin アカウントは引き続きローカル DB 認証でログイン可能。

## 既知の制約

- Authentik 自体が現状 HTTP 直公開（TLS 未設定、Phase 9 待ち）のため、
  `oidc_verify_cert = false` にしている。OIDC ディスカバリの実装によっては
  HTTPS でない issuer を拒否することがあるため、HTTP のままでは
  ログインが実際に通るかは未検証（`harbor_config_auth` の apply・
  `auth_mode` が `oidc_auth` になることまでは確認済み）。実際にログインまで
  通すには Authentik 側の TLS 化が前提になる可能性が高い。
- `oidc_admin_group` は未設定（対応する Authentik 管理者グループがまだ無いため）。
  将来 `catalog/teams/` 等で管理者グループができたら設定する。
- docker login/push/pull は OIDC ログインではなく、Harbor UI から発行される
  CLI Secret を使う（Authentik のパスワードではログインできない）。
