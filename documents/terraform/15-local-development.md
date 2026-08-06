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
│  Ubuntu 24.04 VM (16GB RAM / 4 CPU)         │
│    └─ DevStack (OpenStack)  :5000 (Keystone)│
└─────────────────────────────────────────────┘
```

DevStack は WSL2 上では systemd や Neutron ネットワークの制限で
正常動作しないことが多いため、**専用 VM** での起動を推奨します。
VirtualBox / VMware / 手元の Linux マシンで Ubuntu 24.04 を用意してください。

---

## 1. OpenStack（kolla-ansible）

kolla-ansible は OpenStack の各サービスを Docker コンテナとして起動する
公式のデプロイツールです。DevStack より安定しており、本番に近い構成で動作します。

> **WSL2 では動作しません。** Neutron が使う Open vSwitch は
> WSL2 のカーネルでは正常動作しないため、専用の Ubuntu 24.04 VM が必要です。

### 必要リソース

| 項目 | 最小 | 推奨 |
| --- | --- | --- |
| RAM | 8 GB | 16 GB |
| CPU | 2 コア | 4 コア |
| ディスク | 50 GB | 80 GB |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| NIC | 2 つ | 2 つ（管理用 + 外部ネットワーク用） |

### セットアップ

```bash
# 依存パッケージのインストール
sudo apt update
sudo apt install -y python3-dev python3-pip python3-venv git

# 仮想環境を作成して kolla-ansible をインストール
python3 -m venv /opt/kolla-venv
source /opt/kolla-venv/bin/activate
pip install kolla-ansible

# 設定ディレクトリを準備
sudo mkdir -p /etc/kolla
sudo chown $USER /etc/kolla
cp /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/globals.yml /etc/kolla/
cp /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/passwords.yml /etc/kolla/
```

`/etc/kolla/globals.yml` を編集します。

```yaml
# /etc/kolla/globals.yml（主要項目のみ）
kolla_base_distro: "ubuntu"
openstack_release: "2025.2"

# ネットワーク設定（ip addr で確認した NIC 名に変更）
network_interface: "eth0"         # 管理ネットワーク NIC
neutron_external_interface: "eth1" # 外部ネットワーク NIC

kolla_internal_vip_address: "192.168.x.x"  # 管理 NIC の IP

# 有効化するサービス
enable_cinder: "yes"
enable_designate: "yes"
enable_barbican: "yes"
enable_octavia: "yes"

# 無効化するサービス（初期は不要）
enable_trove: "no"
enable_manila: "no"
```

```bash
# パスワードを自動生成
kolla-genpwd

# Docker をインストール（未インストールの場合）
kolla-ansible install-deps

# All-in-one デプロイ（20〜40 分）
kolla-ansible -i /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one \
  bootstrap-servers
kolla-ansible -i /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one \
  prechecks
kolla-ansible -i /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one \
  deploy
```

### 認証情報の確認

```bash
# admin-openrc.sh を生成
kolla-ansible -i .../all-in-one post-deploy
source /etc/kolla/admin-openrc.sh

# 動作確認
openstack project list
openstack network list
```

### Terraform プロバイダー設定

```hcl
# local/local-override.tf.example をコピーして編集
# terraform/local-override.tf（.gitignore 済み）
provider "openstack" {
  auth_url    = "http://192.168.x.x:5000"
  user_name   = "admin"
  password    = "</etc/kolla/passwords.yml の keystone_admin_password>"
  tenant_name = "admin"
  domain_name = "Default"
  region      = "RegionOne"
  insecure    = true
}
```

### ローカル State バックエンド

Ceph RGW の代わりにローカルファイルを使います。
`-backend=false` で state なしで plan のみ確認できます。

```bash
terraform init -backend=false
terraform plan
```

---

## 2. Authentik (Docker Compose)

### docker-compose.yml

リポジトリの `local/` ディレクトリに配置します。

```yaml
# local/authentik/docker-compose.yml
services:
  postgresql:
    image: docker.io/library/postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: ${PG_PASS}
      POSTGRES_USER: authentik
      POSTGRES_DB: authentik
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d authentik -U authentik"]
      interval: 10s
      timeout: 5s
      retries: 5

  server:
    image: ghcr.io/goauthentik/server:2025.10
    command: server
    environment:
      AUTHENTIK_REDIS__HOST: ""   # 2025.10 以降 Redis 不要
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_ERROR_REPORTING__ENABLED: "false"
    ports:
      - "9000:9000"
      - "9443:9443"
    depends_on:
      postgresql:
        condition: service_healthy

  worker:
    image: ghcr.io/goauthentik/server:2025.10
    command: worker
    environment:
      AUTHENTIK_REDIS__HOST: ""
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
    depends_on:
      postgresql:
        condition: service_healthy

volumes:
  pg_data:
```

```bash
# local/authentik/.env
PG_PASS=localdev
AUTHENTIK_SECRET_KEY=<openssl rand -base64 36 で生成>
```

```bash
# 起動
cd local/authentik
openssl rand -base64 36 | tr -d '\n' > .env.secret
echo "PG_PASS=localdev" >> .env
echo "AUTHENTIK_SECRET_KEY=$(cat .env.secret)" >> .env

docker compose up -d
```

### 初期設定

1. <http://localhost:9000/if/flow/initial-setup/> にアクセス
2. `akadmin` のパスワードを設定
3. 管理画面: <http://localhost:9000/if/admin/>

### Terraform プロバイダー用トークン

管理画面 → `Admin Interface` → `Directory` → `Tokens` → `Create Token`
スコープ: `API access`

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
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# クラスター作成
kind create cluster --name lc-local

# kubectl の確認
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

# 環境変数
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

# KV シークレットエンジンを有効化
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

## 5. 全サービス起動スクリプト

```bash
# local/start.sh
#!/usr/bin/env bash
set -e

echo "=== Authentik 起動 ==="
cd "$(dirname "$0")/authentik"
docker compose up -d
cd -

echo "=== Vault 起動 ==="
docker start vault-dev 2>/dev/null || docker run -d \
  --name vault-dev \
  -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  hashicorp/vault

echo "=== kind クラスター確認 ==="
kind get clusters | grep -q lc-local \
  || kind create cluster --name lc-local

echo ""
echo "Authentik : http://localhost:9000"
echo "Vault     : http://localhost:8200 (token: root)"
echo "K8s       : kind-lc-local"
echo "DevStack  : http://192.168.x.x (別 VM)"
```

```bash
chmod +x local/start.sh
```

---

## 6. 開発フロー

### catalog/projects のテスト

```bash
cd terraform/catalog/projects/_template

# ローカル State でテスト
terraform init -backend=false
terraform plan -var="project_name=test-project" -var="team_name=web"
```

### Application Credential の動作確認

```bash
# DevStack で Application Credential を作成して Access Rules をテスト
openstack application credential create test \
  --access-rules '[{"method":"GET","path":"/v2.1/servers"}]'

# 作成した credential で認証してみる
OS_APPLICATION_CREDENTIAL_ID=<id> \
OS_APPLICATION_CREDENTIAL_SECRET=<secret> \
openstack server list

# Access Rules で弾かれるか確認（POST は禁止されているはず）
OS_APPLICATION_CREDENTIAL_ID=<id> \
OS_APPLICATION_CREDENTIAL_SECRET=<secret> \
openstack server create ...   # → 403 になるはず
```

### Authentik フローのテスト

```bash
# Terraform で Authentik グループを作成してみる
cd terraform/catalog/teams/_template
terraform init -backend=false
terraform plan -var="team_name=test-team"
terraform apply -var="team_name=test-team" -auto-approve
```

---

## 7. ローカルと本番の切り替え

`local-override.tf` は git 管理しません。
本番環境では Vault OIDC 認証を使うため、
ローカルの `local-override.tf` を削除するだけで
本番用の provider 設定（Vault から credentials 取得）に戻ります。

```bash
# ローカル開発
cp local-override.tf.example terraform/local-override.tf
# → providers が localhost を向く

# 本番
rm terraform/local-override.tf
# → providers が vault-action から取得した credentials を使う
```

---

## 参考リンク

- [kolla-ansible クイックスタート](https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html)
- [kolla-ansible Ubuntu 24.04 インストールガイド](https://superuser.openinfra.org/articles/kolla-ansible-openstack-installation-ubuntu-24-04/)
- [Authentik Docker Compose インストール](https://version-2025-4.goauthentik.io/docs/install-config/install/docker-compose)
- [kind クイックスタート](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Vault dev モード](https://developer.hashicorp.com/vault/docs/concepts/dev-server)
