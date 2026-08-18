# ローカル開発環境

本番の LC-Cloud (OpenStack) と Authentik がなくても、
ローカルで Terraform コードの動作確認ができる環境を構築します。

---

## 構成概要

```text
┌─────────────────────────────────────────────┐
│  開発マシン (WSL2 / Linux / Mac)             │
│                                             │
│  Docker Compose                             │
│    ├─ Authentik (IdP)   :9000              │
│    └─ Vault dev         :8200              │
│                                             │
│  kind                                       │
│    └─ ローカル K8s クラスター               │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  ローカルサーバー (GK41)                     │
│    └─ OpenStack          192.168.1.7        │
│         Keystone  /identity                 │
│         Nova      /compute/v2.1             │
│         Neutron   /networking               │
│         Glance    /image                    │
│         Placement /placement                │
└─────────────────────────────────────────────┘
```

---

## 1. OpenStack（ローカルサーバー GK41）

ローカルネットワーク上の GK41 サーバー（`192.168.1.7`）で
OpenStack が稼働しています。

### 接続設定（clouds.yaml）

認証情報は `local/clouds.yaml` で管理します（`.gitignore` 済み）。

```bash
cp local/clouds.yaml.example local/clouds.yaml
# エディタで app-cred-id と app-cred-secret を入力する
```

```yaml
# local/clouds.yaml
clouds:
  gk41-poc:
    auth:
      auth_url: http://192.168.1.7/identity/
      application_credential_id: "<app-cred-id>"
      application_credential_secret: "<app-cred-secret>"
    auth_type: v3applicationcredential
    region_name: RegionOne
    interface: public
```

`clouds.yaml` のデフォルト探索パスは `~/.config/openstack/` です。
リポジトリ内の `local/clouds.yaml` を使うには `OS_CLIENT_CONFIG_FILE` を設定します。

```bash
export OS_CLIENT_CONFIG_FILE="$(pwd)/local/clouds.yaml"
export OS_CLOUD=gk41-poc
```

> **Tips**: `.envrc`（direnv）に書いておくと自動で読み込まれます。

### Application Credential の発行

Terraform 用には `admin` ロールの Credential を発行します。

```bash
export OS_CLOUD=gk41-poc

openstack application credential create dev-terraform \
  --role admin \
  --description "ローカル開発用 Terraform 認証"
```

### 動作確認

```bash
export OS_CLIENT_CONFIG_FILE="$(pwd)/local/clouds.yaml"
export OS_CLOUD=gk41-poc

openstack project list
openstack network list
openstack server list
```

### Terraform プロバイダー設定

```bash
cp local/local-override.tf.example terraform/local-override.tf
# terraform/local-override.tf は .gitignore 済み
```

```hcl
# terraform/local-override.tf
provider "openstack" {
  # OS_CLIENT_CONFIG_FILE / OS_CLOUD を読む
  cloud = "gk41-poc"
}
```

```bash
export OS_CLIENT_CONFIG_FILE="$(pwd)/local/clouds.yaml"
export OS_CLOUD=gk41-poc

cd terraform/catalog/projects/_template
terraform init -backend=false
terraform plan -var="project_name=test-project" -var="team_name=web"
```

---

## 2. Authentik (Docker Compose)

### バージョンについて

`:latest` タグは `2025.2` 以降 deprecated のため、必ず固定バージョンを使います。
最新版は [GitHub Releases](https://github.com/goauthentik/authentik/releases) で確認してください。

### 起動

```bash
# 初回のみ: .env を生成して起動
cd local/authentik
cp .env.example .env
SECRET=$(openssl rand -base64 36 | tr -d '\n')
sed -i "s/change-me-generate-with-openssl-rand-base64-36/$SECRET/" .env
docker compose up -d
```

```bash
# 2 回目以降
docker compose -f local/authentik/docker-compose.yml up -d
```

### 初期設定

1. <http://localhost:9000/if/flow/initial-setup/> にアクセス
1. `akadmin` のパスワードを設定
1. 管理画面: <http://localhost:9000/if/admin/>

### Terraform プロバイダー用トークン

管理画面 → `Admin Interface` → `Directory` → `Tokens` → `Create Token`（スコープ: `API access`）

```hcl
# terraform/local-override.tf に追記
provider "authentik" {
  url   = "http://localhost:9000"
  token = "<生成したトークン>"
}
```

---

## 3. kind (ローカル K8s)

```bash
# kind インストール（Linux）
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# クラスター作成
kind create cluster --name lc-local

# 確認
kubectl cluster-info --context kind-lc-local
kubectl get nodes
```

k8s-api の動作確認はこのクラスターを使います。

---

## 4. Vault (dev モード)

```bash
# Docker で起動
docker run -d \
  --name vault-dev \
  -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  hashicorp/vault

# KV シークレットエンジンを有効化
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root
vault secrets enable -path=kv -version=2 kv

# 動作確認
vault kv put kv/app-creds/test app-cred-id=dummy app-cred-secret=dummy
vault kv get kv/app-creds/test
```

```hcl
# terraform/local-override.tf に追記
provider "vault" {
  address = "http://localhost:8200"
  token   = "root"
}
```

---

## 5. 全サービス起動

`local/start.sh` で Authentik・Vault・kind を一括起動できます。

```bash
bash local/start.sh
```

起動後に表示される `OS_CLIENT_CONFIG_FILE` と `OS_CLOUD` を
シェルに設定してから Terraform や OpenStack CLI を使います。

---

## 6. 開発フロー

### Application Credential と Access Rules のテスト

```bash
export OS_CLIENT_CONFIG_FILE="$(pwd)/local/clouds.yaml"
export OS_CLOUD=gk41-poc

# Access Rules 付きの Credential を作成
openstack application credential create test-readonly \
  --access-rules '[{"method":"GET","path":"/v2.1/servers"}]'

# 作成した Credential で認証（GET は通る）
OS_CLOUD="" \
OS_AUTH_URL=http://192.168.1.7/identity/ \
OS_APPLICATION_CREDENTIAL_ID=<id> \
OS_APPLICATION_CREDENTIAL_SECRET=<secret> \
openstack server list

# POST は Access Rules で弾かれることを確認（→ 403）
OS_CLOUD="" \
OS_AUTH_URL=http://192.168.1.7/identity/ \
OS_APPLICATION_CREDENTIAL_ID=<id> \
OS_APPLICATION_CREDENTIAL_SECRET=<secret> \
openstack server create ...
```

### Authentik フローのテスト

```bash
cd terraform/catalog/teams/_template
terraform init -backend=false
terraform plan -var="team_name=test-team"
terraform apply -var="team_name=test-team" -auto-approve
```

---

## 7. ローカルと本番の切り替え

`terraform/local-override.tf` は git 管理しません。
本番では Vault OIDC 認証を使うため、このファイルを削除するだけで戻ります。

```bash
# ローカル開発
cp local/local-override.tf.example terraform/local-override.tf

# 本番
rm terraform/local-override.tf
```

---

## 参考リンク

- [OpenStack Application Credentials](https://docs.openstack.org/keystone/latest/user/application_credentials.html)
- [Terraform OpenStack Provider — cloud 設定](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs#configuration-reference)
- [clouds.yaml リファレンス](https://docs.openstack.org/python-openstackclient/latest/configuration/index.html)
- [Authentik Docker Compose インストール](https://version-2025-4.goauthentik.io/docs/install-config/install/docker-compose)
- [kind クイックスタート](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Vault dev モード](https://developer.hashicorp.com/vault/docs/concepts/dev-server)
