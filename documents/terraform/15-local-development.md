# ローカル開発環境

本番の LC-Cloud (OpenStack) と Authentik がなくても、
ローカルで Terraform コードの動作確認ができる環境を構築します。

---

## 必要なツール

| ツール | 用途 | インストール |
| --- | --- | --- |
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | GCP VM への IAP トンネル・SSH | Google Cloud SDK |
| [Terraform](https://developer.hashicorp.com/terraform/install) | IaC 実行・GCP VM 構築 | `tfenv` 推奨 |
| [Docker](https://docs.docker.com/engine/install/) + Compose | Authentik 起動・act ランナー | Docker Desktop または Engine |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | ローカル K8s クラスター | `curl` でバイナリ取得 |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | K8s 操作 | gcloud components または単体 |
| [openstack CLI](https://docs.openstack.org/python-openstackclient/latest/) | Application Credential 発行・動作確認 | `pip install python-openstackclient` |
| [PySocks](https://pypi.org/project/PySocks/) | openstack CLI の SOCKS5 プロキシ対応 | `pip install pysocks` |
| [act](https://github.com/nektos/act) | GitHub Actions ローカル実行 | Section 4 参照 |

> **WSL2 の場合**: Docker Desktop（Windows 側）を WSL2 バックエンドで動かすか、
> WSL2 内に Docker Engine を直接インストールしてください。

---

## 構成概要

```text
┌─────────────────────────────────────────────┐
│  開発マシン (Windows + WSL2)                 │
│                                             │
│  Docker Compose                             │
│    ├─ Authentik (IdP)   :9000              │
│    └─ Vault dev         :8200              │
│                                             │
│  kind                                       │
│    └─ ローカル K8s クラスター               │
│                                             │
│  gcp-devstack/windows-autostop              │
│    └─ アイドル/スリープ検知で GCP VM を自動停止 │
└─────────────────────────────────────────────┘
              │ IAP トンネル (SSH / 80 / 8080)
              ▼
┌─────────────────────────────────────────────┐
│  GCP VM (local/gcp-devstack/, e2-standard-4) │
│    OpenStack (DevStack)      :80             │
│         Keystone  /identity                 │
│         Nova      /compute/v2.1              │
│         Neutron   /networking                │
│         Glance    /image                     │
│         Placement /placement                 │
│         Horizon   /                          │
│    Harbor（最小構成）         :8080          │
└─────────────────────────────────────────────┘
```

DevStack + Harbor は GCP の専用 VM 上で稼働します。VM は作業時のみ起動し、
使わないときは自動停止（後述）してコストを抑えます。

---

## 1. OpenStack + Harbor（GCP VM）

`local/gcp-devstack/` の Terraform で GCP 上に DevStack（OpenStack）と
Harbor（コンテナレジストリ、最小構成）を同居させた VM を構築します。
ファイアウォールは IAP（Identity-Aware Proxy）レンジのみ許可しており、
SSH・OpenStack API・Harbor いずれもインターネットには公開されません。

### VM の構築

```bash
gcloud auth login
gcloud auth application-default login

cd local/gcp-devstack
cp terraform.tfvars.example terraform.tfvars
# project_id / devstack_admin_password / harbor_admin_password を入力する

terraform init
terraform plan
terraform apply
```

初回起動時は VM の startup-script が Docker・DevStack・Harbor を
自動インストールします（`stack.sh` に時間がかかるため 20〜40 分程度）。
進捗は VM 上の `/var/log/gcp-devstack-bootstrap.log` で確認できます。

```bash
gcloud compute ssh $(terraform output -raw instance_name) \
  --tunnel-through-iap --zone=$(terraform output -raw zone) \
  --command="tail -f /var/log/gcp-devstack-bootstrap.log"
```

> IAP トンネルを使うには、自分の GCP アカウントに
> `roles/iap.tunnelResourceAccessor` ロールが必要です。
> `gcloud projects add-iam-policy-binding <project> --member=user:<you> --role=roles/iap.tunnelResourceAccessor`

### 接続設定（IAP トンネル + clouds.yaml）

ファイアウォールが IAP レンジのみ許可のため、ローカルから使う前に
IAP トンネルを張ります。

```bash
./local/gcp-devstack/start-tunnels.sh
# OpenStack API/Horizon: http://localhost:18080/
# Harbor:                http://localhost:18081/
```

認証情報は `local/clouds.yaml` で管理します（`.gitignore` 済み）。

```bash
cp local/clouds.yaml.example local/clouds.yaml
# エディタで app-cred-id と app-cred-secret を入力する
```

```yaml
# local/clouds.yaml
clouds:
  gcp-devstack:
    auth:
      auth_url: http://localhost:18080/identity/
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
export OS_CLOUD=gcp-devstack
```

> **Tips**: `.envrc`（direnv）に書いておくと自動で読み込まれます。

### SOCKS5 プロキシ（サービスカタログ越しのアクセスに必須）

DevStack のサービスカタログは `HOST_IP`（VM 内部プライベート IP、例:
`10.10.0.2`）を全エンドポイントのベース URL として返します。
`openstack token issue` のような `auth_url` に対する単発リクエストは
IAP トンネル（`localhost:18080`）だけで動きますが、それ以外の
ほぼ全ての操作（Application Credential 発行、`project list` /
`network list` / `server list`、Terraform openstack プロバイダー等）は
認証後にサービスカタログの URL（`http://10.10.0.2/...`）へ直接
アクセスしようとします。`10.10.0.2` は GCP VPC 内プライベート IP で、
ローカル PC からは到達不能（IAP トンネルは固定ポートの
ポートフォワードのみで、任意 IP へのルーティングではない）なため、
そのままだと接続が永久にハングします。

対処として SSH の SOCKS5 プロキシ（IAP トンネル経由）を別途立てます。

```bash
gcloud compute ssh devstack-harbor \
  --tunnel-through-iap --zone=<zone> -- -N -D 1080 &
```

`openstack` / `terraform` 実行時は、`ALL_PROXY` で `10.10.0.2` 宛の
通信だけ SOCKS5 プロキシに流し、`localhost`（IAP トンネル向け）は
`NO_PROXY` で除外します（除外しないと `auth_url` への最初のリクエスト
自体が SOCKS プロキシ越しになり、VM 自身から見た `localhost` を
指してしまい失敗する）。

```bash
export ALL_PROXY=socks5h://localhost:1080
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1
```

`openstack` CLI の Python 環境に `PySocks`（`pip install pysocks`）が
必要です。`requests` ライブラリが `socks5h://` を解釈できるようにする
ためのパッケージで、無ければ `SOCKSHTTPConnectionPool ... Failed to
establish a new connection` のようなエラーになります。

### Application Credential の発行

Terraform 用には `admin` ロールの Credential を発行します
（IAP トンネル起動後、`OS_AUTH_URL` は Keystone の初期 admin 認証で
一度だけパスワード認証する必要があります。パスワードは
`terraform.tfvars` の `devstack_admin_password`）。

この時点ではまだ `local/clouds.yaml` に Credential が無いため、
admin のユーザー名/パスワードで直接認証する（前掲の SOCKS5 プロキシは
必須）。

```bash
export OS_AUTH_URL=http://localhost:18080/identity/
export OS_USERNAME=admin
export OS_PASSWORD="<terraform.tfvars の devstack_admin_password>"
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
export ALL_PROXY=socks5h://localhost:1080
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1

openstack application credential create dev-terraform \
  --role admin \
  --description "ローカル開発用 Terraform 認証"
```

出力された `id` / `secret` を `local/clouds.yaml` の `gcp-devstack`
エントリーに書き込む。

### 動作確認

```bash
export OS_CLIENT_CONFIG_FILE="$(pwd)/local/clouds.yaml"
export OS_CLOUD=gcp-devstack
export ALL_PROXY=socks5h://localhost:1080
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1

openstack project list
openstack network list
openstack server list
```

### Harbor へのログイン

IAP トンネル起動後、`http://localhost:18081` に admin /
`terraform.tfvars` の `harbor_admin_password` でログインできます。

```bash
docker login localhost:18081
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
  cloud = "gcp-devstack"
}
```

```bash
export OS_CLIENT_CONFIG_FILE="$(pwd)/local/clouds.yaml"
export OS_CLOUD=gcp-devstack
export ALL_PROXY=socks5h://localhost:1080
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1

cd terraform/catalog/projects/_template
terraform init -backend=false
terraform plan -var="project_name=test-project" -var="team_name=web"
```

### VM の起動・停止

作業終了後は VM を止めてコストを抑えます（下記「アイドル自動停止」で
自動化もできます）。

```bash
# WSL / Linux から
./local/gcp-devstack/windows-autostop/start-vm.sh
./local/gcp-devstack/windows-autostop/stop-vm.sh

# Windows (PowerShell) から
.\local\gcp-devstack\windows-autostop\start-vm.ps1
.\local\gcp-devstack\windows-autostop\stop-vm.ps1
```

いずれも `local/gcp-devstack/windows-autostop/config.env` の設定を使います
（`config.env.example` をコピーし `terraform output` の値を入力）。

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

## 4. GitHub Actions (act)

GitHub Actions ワークフローをローカルで実行するために
[act](https://github.com/nektos/act) を使います。
`terraform validate` / `terraform fmt` / `terraform plan` を
CI と同じ流れで確認できます。

### インストール

```bash
# Linux (amd64)
curl -s https://api.github.com/repos/nektos/act/releases/latest \
  | grep "browser_download_url.*Linux_x86_64.tar.gz" \
  | cut -d '"' -f 4 \
  | xargs curl -Lo act.tar.gz
tar xzf act.tar.gz act
sudo mv act /usr/local/bin/act
rm act.tar.gz
act --version
```

### シークレットと環境変数の設定

```bash
cp local/.secrets.example local/.secrets
cp local/.act.env.example local/.act.env
```

`local/.secrets` を編集して値を入力します。

| キー | 値の取得元 |
| --- | --- |
| `AUTHENTIK_TOKEN` | ローカル Authentik 管理画面 → Directory → Tokens |
| `LC_CLOUD_APP_CRED_ID` | `openstack application credential show <name>` |
| `LC_CLOUD_APP_CRED_SECRET` | Application Credential 作成時に表示される secret |
| `SOPS_AGE_KEY` | `age-keygen` で生成した秘密鍵（`AGE-SECRET-KEY-...`） |

`local/.act.env` は変更不要です（`TF_CLI_ARGS_init=-backend=false` が設定済み）。

リポジトリルートの `.actrc` に共通設定が書かれており、`act` 実行時に自動で読み込まれます。

### 実行

```bash
# plan ワークフローをローカルで実行（特定スタックを対象に）
act pull_request \
  -W .github/workflows/plan.yml \
  --matrix stack:terraform/catalog/teams/_template

# modules-check ワークフローをローカルで実行
act pull_request \
  -W .github/workflows/modules-check.yml
```

初回実行時に Docker イメージ（`catthehacker/ubuntu:act-latest`、約 800 MB）を
ダウンロードするため時間がかかります。

### ローカル実行の制限事項

| 項目 | 挙動 |
| --- | --- |
| PR コメント投稿 | GitHub API を呼ぶため失敗するが CI 結果には影響しない |
| 変更ファイル検出 | `git diff` がローカルの状態を返す（origin/main との差分） |
| S3 バックエンド | `TF_CLI_ARGS_init=-backend=false` で無効化済み |
| `environment: production` ゲート | ローカルではスキップされる |

---

## 5. 全サービス起動

`local/start.sh` で Authentik・kind を一括起動できます。

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
export OS_CLOUD=gcp-devstack
export ALL_PROXY=socks5h://localhost:1080
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1

# Access Rules 付きの Credential を作成
openstack application credential create test-readonly \
  --access-rules '[{"method":"GET","path":"/v2.1/servers"}]'

# 作成した Credential で認証（GET は通る。IAP トンネル起動済みが前提）
OS_CLOUD="" \
OS_AUTH_URL=http://localhost:18080/identity/ \
OS_APPLICATION_CREDENTIAL_ID=<id> \
OS_APPLICATION_CREDENTIAL_SECRET=<secret> \
openstack server list

# POST は Access Rules で弾かれることを確認（→ 403）
OS_CLOUD="" \
OS_AUTH_URL=http://localhost:18080/identity/ \
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
本番では GitHub Secrets の認証情報を CI が使うため、このファイルを削除するだけで戻ります。

```bash
# ローカル開発
cp local/local-override.tf.example terraform/local-override.tf

# 本番
rm terraform/local-override.tf
```

---

## 8. アイドル自動停止

### VM 側（メイン）

GCP VM には起動時から **idle-shutdown** systemd タイマーが有効になっており、
**IAP トンネル（SSH 接続）が 30 分間途絶えると VM 自身がシャットダウン**します。
`bootstrap.sh` が初回起動時に `/usr/local/bin/idle-shutdown.sh` と
`idle-shutdown.timer` をインストールするため、追加のセットアップは不要です。

```bash
# VM 上でタイマーの状態を確認する（SSH 接続中に実行）
gcloud compute ssh devstack-harbor --tunnel-through-iap --zone=<zone> \
  --command="systemctl status idle-shutdown.timer"

# ログを確認する
gcloud compute ssh devstack-harbor --tunnel-through-iap --zone=<zone> \
  --command="journalctl -t idle-shutdown"
```

IAP トンネル（`start-tunnels.sh`）を閉じると SSH 接続が切れ、30 分後に
VM が自動停止します。作業中はトンネルを開いたままにしてください。

### PC 側（補助）

PC がスリープした場合でもすぐに VM を止めたいときは
`local/gcp-devstack/windows-autostop/` の Windows タスクスケジューラを使います。

```bash
cp local/gcp-devstack/windows-autostop/config.env.example \
   local/gcp-devstack/windows-autostop/config.env
# PROJECT_ID / ZONE / INSTANCE_NAME を terraform output の値で埋める
```

PowerShell を「管理者として実行」で開き、タスクを登録します。

```powershell
cd local\gcp-devstack\windows-autostop
.\register-scheduled-tasks.ps1
```

| タスク名 | トリガー | 動作 |
| --- | --- | --- |
| `GCPDevStackIdleCheck` | 10 分おき | 無操作 30 分を超えていたら VM を停止 |
| `GCPDevStackSleepStop` | PC スリープ移行時 | 即座に VM を停止 |

タスクは VBScript の隠しランチャー経由で PowerShell を起動するため、
実行時にコンソールウィンドウが前面に出ることはありません。
以前のバージョンで登録した場合は `register-scheduled-tasks.ps1` を再実行してください
（`/f` で上書き登録されます）。

```powershell
# 削除
schtasks /delete /tn GCPDevStackIdleCheck /f
schtasks /delete /tn GCPDevStackSleepStop /f
```

---

## 参考リンク

- [OpenStack Application Credentials](https://docs.openstack.org/keystone/latest/user/application_credentials.html)
- [Terraform OpenStack Provider — cloud 設定](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs#configuration-reference)
- [clouds.yaml リファレンス](https://docs.openstack.org/python-openstackclient/latest/configuration/index.html)
- [Authentik Docker Compose インストール](https://version-2025-4.goauthentik.io/docs/install-config/install/docker-compose)
- [kind クイックスタート](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [DevStack](https://docs.openstack.org/devstack/latest/)
- [Harbor インストールガイド](https://goharbor.io/docs/latest/install-config/)
- [IAP で TCP 転送を使う](https://cloud.google.com/iap/docs/using-tcp-forwarding)
