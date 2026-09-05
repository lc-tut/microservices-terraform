# 本番構築手順書

各フェーズを順番に実施します。次フェーズに進む前に必ず検証セクションを確認してください。

設計の背景・決定事項は `16-implementation-phases.md` を参照してください。

---

## 前提条件

| 項目 | 内容 |
| --- | --- |
| OpenStack | 本番 OpenStack が稼働していること |
| admin Application Credential | `admin` ロールを持つ Application Credential が手元にあること |
| GitHub Organization | `linuxclub` Organization が作成済みであること |
| ドメイン | `lc-cloud.example.internal` が内部 DNS に登録されていること |
| K8s クラスター | LC-Cloud 上に Kubernetes クラスターが存在すること（Phase 2 以降で使用） |

---

## Phase 1 — GitHub / CI 基盤

### 1-1. GitHub Secrets の登録

GitHub Organization → **Settings → Secrets and variables → Actions** で以下を登録します。

| Secret 名 | 値 | 取得方法 |
| --- | --- | --- |
| `AUTHENTIK_TOKEN` | Authentik API トークン | Phase 2 完了後に更新（仮値 `placeholder` で先に登録可） |
| `LC_CLOUD_APP_CRED_ID` | OpenStack Application Credential ID | 下記手順で取得 |
| `LC_CLOUD_APP_CRED_SECRET` | OpenStack Application Credential Secret | 下記手順で取得 |
| `SOPS_AGE_KEY` | age 秘密鍵 | `age-keygen` で生成 |
| `HARBOR_ADMIN_PASSWORD` | Harbor 管理者パスワード | Phase 4 完了後に更新 |
| `CEPH_RGW_ENDPOINT` | Ceph RGW の S3 エンドポイント URL | 例: `https://s3.lc-cloud.example.internal` |
| `CEPH_ACCESS_KEY_ID` | Ceph RGW S3 アクセスキー | Ceph 管理者から取得 |
| `CEPH_SECRET_ACCESS_KEY` | Ceph RGW S3 シークレットキー | Ceph 管理者から取得 |

**admin Application Credential の作成:**

```bash
export OS_CLOUD=<本番クラウド名>
export OS_CLIENT_CONFIG_FILE=/path/to/clouds.yaml

openstack application credential create terraform-ci \
  --description "GitHub Actions CI/CD 用" \
  --unrestricted
# → 出力された id と secret を Secret に登録する
```

**age キーの生成:**

```bash
age-keygen -o terraform-ci.age
cat terraform-ci.age   # 秘密鍵（SOPS_AGE_KEY に登録）

# 公開鍵はリポジトリの .sops.yaml に記載
age-keygen -y terraform-ci.age  # 公開鍵のみ出力
```

`.sops.yaml` をリポジトリルートに配置します:

```yaml
creation_rules:
  - path_regex: .*\.enc\.yaml$
    age: >-
      <公開鍵をここに貼る>
```

### 1-2. State バックエンドの作成

Ceph RGW に `linuxclub-tfstate` バケットを作成します。

```bash
# Ceph RGW の S3 互換 CLI で作成
aws s3 mb s3://linuxclub-tfstate \
  --endpoint-url https://s3.lc-cloud.example.internal \
  --region us-east-1
```

### 1-3. GitHub Organization の初期設定

```bash
# circle-admin チームの作成
gh api orgs/linuxclub/teams \
  --method POST \
  --field name="circle-admin" \
  --field privacy="closed"

# Branch Protection は Terraform で管理する（Step 1-5 で apply）
```

### 1-4. GitHub Actions ワークフローのデプロイ

`06-cicd.md` に記載されたワークフロー YAML を直接コミットします（CI が存在しない状態なので手動で push）。

```bash
mkdir -p .github/workflows

# 06-cicd.md から plan.yml / apply.yml / modules-check.yml /
# codeowners-check.yml を抜き出してファイルに保存する

git add .github/workflows/
git commit -m "ci: add GitHub Actions workflows"
git push origin main
```

### 1-5. `terraform/platform/github/` の初回 apply（手動）

CI が存在しない段階での bootstrap なので、circle-admin がローカルから apply します。

```bash
cd terraform/platform/github

# backend.tf の key を設定済みであること
export OS_CLOUD=<本番クラウド名>
export OS_CLIENT_CONFIG_FILE=/path/to/clouds.yaml

terraform init
terraform plan
terraform apply
```

**検証:**

```bash
# CI が動作することを確認するためにテスト PR を作成する
gh pr create --title "chore: CI smoke test" --body "CI 動作確認用"
# plan ワークフローが自動実行され、PR にコメントが投稿されることを確認
gh pr close --delete-branch <PR番号>
```

---

## Phase 2 — Authentik（IdP）

### 2-1. Authentik 本番インスタンスのデプロイ

#### 現状（最小構成 / 実機検証済み） — `terraform/platform/infra/idp-infra/`

マネージド Kubernetes 基盤が存在しない環境向けに、**単一 VM + Docker Compose** の
最小構成を `terraform/platform/infra/idp-infra/` で IaC 管理している。
VM スペック・ネットワーク・Security Group・cloud-init の内容・既知の問題
（Docker のインストール周り等）は同ディレクトリの `README.md` を参照。

`AUTHENTIK_SECRET_KEY` / postgres パスワード / akadmin パスワード / API トークンは
`random_*` で新規生成し tfstate にのみ保存する。

```bash
export OS_CLIENT_CONFIG_FILE=/path/to/local/clouds.yaml
cd terraform/platform/infra/idp-infra
terraform init && terraform apply

terraform output -raw authentik_url               # → 2-3 の TF_VAR_authentik_url
terraform output -raw authentik_token             # → 2-2 の AUTHENTIK_TOKEN（手動発行不要）
terraform output -raw authentik_akadmin_password  # akadmin Web ログイン用
```

> **食い違い注記**: `## 前提条件` の「LC-Cloud 上に K8s クラスターが存在すること」は
> 現状の環境ではまだ満たされていない。下記 Helm 手順は将来 K8s 基盤ができた
> 時点の本番像であり、**未検証**。当面は上記 VM 構成で Phase 2 以降を進める。

#### 将来（K8s 基盤ができたら） — Helm

```bash
# Helm を使う場合（未検証。Redis は chart 同梱）
helm repo add authentik https://charts.goauthentik.io
helm repo update

helm upgrade --install authentik authentik/authentik \
  --namespace authentik \
  --create-namespace \
  --set authentik.secret_key="<ランダム文字列>" \
  --set authentik.postgresql.password="<DBパスワード>" \
  --set authentik.redis.password="<Redisパスワード>" \
  --set server.ingress.enabled=true \
  --set server.ingress.hosts[0].host="auth.lc-cloud.example.internal"
```

### 2-2. Authentik API トークンの取得

**VM 構成（現状）**: `idp-infra` が `AUTHENTIK_BOOTSTRAP_TOKEN` を注入して akadmin 用
トークンを起動時に自動発行するため、手動発行は不要。

```bash
gh secret set AUTHENTIK_TOKEN \
  --body "$(cd terraform/platform/infra/idp-infra && terraform output -raw authentik_token)"
```

**Helm 構成（将来）**: 初期セットアップウィザードを完了し、
**Admin → Directory → Tokens → Create** でトークンを作成して同様に登録する。

### 2-3. `terraform/platform/idp/` の apply

Phase 1 の CI を使って PR 経由で apply します。

```bash
# ブランチを切って PR → merge で CI が apply する
git checkout -b feat/platform-idp-initial
# terraform/platform/idp/ の実装を追加
git add terraform/platform/idp/
git commit -m "feat(idp): initial Authentik setup"
git push origin feat/platform-idp-initial
gh pr create --title "feat(idp): initial Authentik setup"
# CODEOWNERS 承認 → merge → apply
```

**検証:**

```bash
# 入会フローが開けること
curl -I https://auth.lc-cloud.example.internal/if/flow/member-enrollment/

# Authentik API が応答すること
curl -H "Authorization: Bearer <AUTHENTIK_TOKEN>" \
  https://auth.lc-cloud.example.internal/api/v3/core/groups/
```

---

## Phase 3 — OpenStack platform

### 3-1. `terraform/platform/openstack/network/` の apply

VPC Gateway・subnetpool・外部ネットワークを作成します。

```bash
git checkout -b feat/platform-network
# terraform/platform/openstack/network/ を実装
git add terraform/platform/openstack/network/
git commit -m "feat(network): VPC gateway and subnetpool"
git push && gh pr create ...
# 承認 → merge → apply
```

### 3-2. `terraform/platform/openstack/images/` の apply

SSH CA 組み込み済みの Ubuntu 24.04 ベースイメージを登録します。

```bash
git checkout -b feat/platform-images
git add terraform/platform/openstack/images/
git commit -m "feat(images): base VM image with SSH CA"
git push && gh pr create ...
```

### 3-3. `terraform/platform/openstack/quotas/` の apply

クォータティア（small / medium / large）を定義します。

```bash
git checkout -b feat/platform-quotas
git add terraform/platform/openstack/quotas/
git commit -m "feat(quotas): quota tier definitions"
git push && gh pr create ...
```

**検証:**

```bash
# subnetpool が存在すること
openstack subnet pool list

# 外部ネットワークが存在すること
openstack network list --external
```

---

## Phase 4 — catalog

### 4-1. `terraform/catalog/teams/` への初期チーム追加

`_template/` をコピーして最初のチームを登録します。

```bash
cp -r terraform/catalog/teams/_template \
      terraform/catalog/teams/infra

# variables.tf で team_name = "infra" を設定
# authentik.tf・outputs.tf を確認

git checkout -b feat/catalog-team-infra
git add terraform/catalog/teams/infra/
git commit -m "feat(catalog/teams): add infra team"
git push && gh pr create ...
# 承認 → merge → apply
```

### 4-2. `terraform/catalog/projects/` への初期プロジェクト追加

チームが apply 完了後、プロジェクトを登録します。

```bash
cp -r terraform/catalog/projects/_template \
      terraform/catalog/projects/my-product

# lc_cloud.tf で project_name・team_name を設定
# harbor.tf は enable_harbor = false で起動（Harbor 未稼働の場合）

git checkout -b feat/catalog-project-my-product
git add terraform/catalog/projects/my-product/
git commit -m "feat(catalog/projects): add my-product"
git push && gh pr create ...
```

apply が完了すると以下が自動作成されます:

- OpenStack Project・Network・Subnet・Router Interface・DNS Zone
- GitHub Secret `LC_CLOUD_APP_CRED_ID_MY_PRODUCT` / `LC_CLOUD_APP_CRED_SECRET_MY_PRODUCT`

**検証:**

```bash
# Authentik グループが存在すること
curl -H "Authorization: Bearer <AUTHENTIK_TOKEN>" \
  https://auth.lc-cloud.example.internal/api/v3/core/groups/?name=infra

# OpenStack Project が存在すること
openstack project list | grep infra

# Subnet が払い出されていること
openstack subnet list | grep my-product

# GitHub Secret が登録されていること
gh secret list | grep MY_PRODUCT
```

---

## Phase 5 — workspace モジュール

`terraform/modules/` 側（`lc-vm`・`lc-k8s-app`・`lc-object-bucket` 等）の実装状況は
`16-implementation-phases.md` を参照してください。ここでは `modules/lc-db`
（Trove）が前提とする、**実機 OpenStack 側での Trove 有効化手順**（kolla-ansible）
を扱います。Trove はコントロールプレーンのサービス追加であり Terraform の範囲外
（インフラ担当が kolla-ansible で実行する）です。

> **確認レベルについての注記（2026-09-05 実機検証済み）**: 以下は実際に
> Polaris 上で Trove を有効化し、ゲストイメージのビルド・データストア登録・
> `openstack database instance create` によるインスタンス起動（`ACTIVE`/
> `HEALTHY`）まで一通り確認済みの手順。実機値・つまずいた点は
> `local/polaris-access.md`（gitignore 済み）に詳細を記録している。
> kolla-ansible・Trove とも他バージョンでは挙動が変わり得るため、
> 別環境で実行する際は `etc/kolla/globals.yml`・`ansible/roles/trove/` を
> 自分のバージョンで確認すること。

### 5-1. `globals.yml` の変更

```yaml
enable_trove: "yes"

# デフォルト(false = multi-tenant)のままで良いか、5-4 のネットワーク要件を
# 確認してから singletenant にするか判断する
# enable_trove_singletenant: "yes"

# Horizon を使っている場合のみ
# enable_horizon_trove: "yes"
```

### 5-2. パスワードの追加生成

既存の `passwords.yml`（初回デプロイ時に生成済み）には Trove 用のパスワードが
無いため、`kolla-genpwd` で不足分だけ追加生成する（既存パスワードは変更されない）。

```bash
kolla-genpwd -p /etc/kolla/passwords.yml
grep trove /etc/kolla/passwords.yml
# trove_database_password: ...
# trove_keystone_password: ...
```

### 5-3. デプロイ

```bash
kolla-ansible -i <inventory> deploy --tags trove,loadbalancer
```

> **実機で確認済みの罠（2026-09-05）**: `--tags trove` だけだと
> `trove-manage db_sync`（bootstrap）が
> `ProxySQL Error: Access denied for user 'trove'` で失敗する。
> `enable_proxysql: true` な環境では、新サービスの DB ユーザーを ProxySQL に
> 認識させる処理（`ansible/roles/proxysql-config/`）が `site.yml` の
> 「Apply role loadbalancer」プレイ（`loadbalancer`/`haproxy`/`keepalived`
> タグ）に属しており、サービス自身のタグだけでは ProxySQL コンテナの
> 再設定・再起動が走らない。新サービスを追加する際は必ず
> `--tags <service>,loadbalancer` を指定する。

Keystone への Service・Endpoint・Service User 登録、Trove 用 DB・DB ユーザー作成は
`ansible/roles/trove/tasks/bootstrap.yml`・`register.yml` で自動的に行われる
（他サービスと同様、手動での `openstack service create` 等は不要）。
Horizon の Trove パネルを有効化した場合は追加で:

```bash
kolla-ansible -i <inventory> reconfigure --tags horizon
```

### 5-4. ネットワーク要件（重要・実機トポロジ依存の設計判断が必要）

`trove-guestagent.conf.j2`（ゲスト DB VM 内で動く trove-guestagent の設定）を
確認すると、ゲスト VM は起動直後に control plane の RabbitMQ
（`rpc_transport_url`）へ直接到達できる必要がある。

- **multi-tenant モード**（`enable_trove_singletenant: false`。デフォルト）:
  ゲスト VM は呼び出したプロジェクト自身のネットワークに直接接続される。
  つまり **各プロジェクトのネットワークから control plane の内部 API 網へ
  経路が無いと動かない**。本リポジトリの
  `12-openstack-resources.md`「VPC Gateway 強制・独自 LB 作成禁止」方針では、
  プロジェクトネットワークは共有外部網経由のみに限定する設計のため、
  そのままでは満たせない可能性が高い。
- **singletenant モード**（`enable_trove_singletenant: true`）:
  ゲスト VM は呼び出し元プロジェクトではなく **Trove 自身の service
  プロジェクト**に作られ、Trove が管理者権限で対象プロジェクトの
  Nova/Cinder/Neutron を代理操作する（`trove.conf` の `nova_proxy_admin_*`・
  `remote_nova_client = trove.common.clients_admin.nova_client_trove_admin`
  等から確認）。内部 API 網へ接続する必要があるネットワークは
  Trove の service プロジェクト用ネットワーク1つだけで済むため、
  プロジェクトごとに経路を空ける multi-tenant モードよりも既存の
  ネットワーク方針と衝突しにくい。

いずれのモードでも、**Trove の service プロジェクト（または各プロジェクト）の
ネットワークから、RabbitMQ が listen しているノード（`om_bind_address`）へ
実際に到達できるか、有効化前に実機で確認すること**。ここは Terraform・
kolla-ansible の変数だけでは解決しない、ネットワークトポロジ側の設計判断。

> **実機確認済み（2026-09-05）**: Polaris では control plane の内部 API 網
> （`kolla_internal_vip_address` のセグメント）と、プロジェクトの外部
> ネットワーク（floating IP プール）が同一 L2/L3 セグメントで、プロジェクトの
> ルーターが外部ゲートウェイ経由で SNAT するため、テナントのプライベート
> サブネット上の VM から RabbitMQ へ追加設定無しで到達できた。
> `enable_trove_singletenant` はデフォルト(false)のまま `openstack database
> instance create` でインスタンスが `ACTIVE`/`HEALTHY` になることを確認済み。
> 他環境では firewalld・iptables でこの到達を塞いでいないか含めて
> 個別に確認すること。

### 5-5. ゲストイメージ・データストアの登録（デプロイ後、Trove 管理者作業）

kolla-ansible は Trove 本体のコンテナは用意するが、**ゲスト DB イメージ自体は
含まれない**。デプロイ後に別途用意する必要がある（この部分は一度きりの
管理者作業で、Terraform 化できない）。

> **2026-09-05 時点でソースから裏取り済みの手順**（`openstack/trove`
> `stable/2026.1` ブランチ）。旧 `trove-integration` リポジトリは
> deprecated で内容は `trove` リポジトリの `integration/` 配下に統合済み。
> この版の Trove は **ゲスト VM 内で DB エンジンを直接インストールせず、
> Docker コンテナとして起動する方式**（`trove.guestagent.utils.docker`）。
> ゲストイメージに必要なのは Docker + `trove-guestagent`（`pip install trove`
> と同じパッケージの `trove-guestagent` エントリポイント）+ 専用の
> docker ネットワークプラグイン（`trove-docker-plugin`）で、DB エンジン
> 本体（例: `mysql:8.0`）はインスタンス作成時にゲストが自動で docker pull
> する。ネイティブパッケージのビルドは不要。

**1. ゲストイメージのビルド**（`disk-image-create`。ビルド用ホストに
インターネットアクセスが必要）:

> **実機の罠（2026-09-05・Rocky Linux 10）**: `disk-image-create` は debian
> 系ツール（`debootstrap` 等）に依存する。Rocky/RHEL 系ホストでは EPEL の
> `debootstrap` パッケージが `dpkg`（→ `libz-ng.so.2` 不在）で依存関係が
> 壊れており `dnf install` できなかった。**Ubuntu コンテナの中でビルドする**
> 方式に切り替えて解決した（kolla 環境なら Docker は既に入っている）。

```bash
git clone --depth 1 --branch stable/2026.1 \
  https://opendev.org/openstack/trove.git /opt/trove-src
mkdir -p ~/images

# ip_forward が無効だと docker のブリッジネットワークが機能しない
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-docker-forward.conf

# --network host: 既存のブリッジ設定が壊れている環境向けの回避策
# -v /dev:/dev: Docker が用意する最小限の /dev には loop デバイスが無く、
#               losetup が "No such file or directory" で失敗するため必須
docker run --rm -it --privileged \
  --network host \
  -v /dev:/dev \
  -v /opt/trove-src:/opt/trove-src \
  -v ~/images:/root/images \
  ubuntu:24.04 bash
```

コンテナの中で:

```bash
apt-get update
apt-get install -y qemu-utils git kpartx debootstrap squashfs-tools \
  python3-pip python3-venv sudo curl

python3 -m venv /root/dib-venv
/root/dib-venv/bin/pip install --upgrade pip setuptools diskimage-builder
source /root/dib-venv/bin/activate

export PATH_TROVE=/opt/trove-src
export ELEMENTS_PATH=${PATH_TROVE}/integration/scripts/files/elements
export DIB_RELEASE=noble          # Ubuntu 24.04。他 root の base image と揃える
export DISTRO_NAME=ubuntu
export DIB_CLOUD_INIT_DATASOURCES="ConfigDrive, OpenStack"
export DIB_CLOUD_INIT_ETC_HOSTS=localhost
export GUEST_USERNAME=ubuntu
export DEV_MODE=false             # true にすると devstack 前提の SCP 経由開発モードになる
export SYNC_LOG_TO_CONTROLLER=False
export HOST_SCP_USERNAME=root
export ESCAPED_PATH_TROVE=$(echo ${PATH_TROVE} | sed 's/\//\\\//g')

disk-image-create -x -a amd64 \
  -o /root/images/trove-guest-ubuntu-noble.qcow2 \
  -t qcow2 \
  --image-size 5 \
  --image-cache /root/.cache/image-create \
  base vm ubuntu-minimal cloud-init-datasources pip-cache guest-agent ubuntu-docker
```

`guest-agent` element が `https://opendev.org/openstack/trove` の
`stable/2026.1` を自動 clone するため、trove-guestagent 自体を別途
pip install する必要はない（コントロールプレーンと同じ `trove` パッケージの
`trove-guestagent` エントリポイントを使う）。ビルドには10分程度かかる。

**2. Glance へ登録**（`--tag trove` を付ける。後述の
`trove-manage --image-tags trove` がこのタグで最新イメージを自動解決する
ため、image_id を都度差し替えなくて済む）:

```bash
source /etc/kolla/admin-openrc.sh
openstack image create trove-guest-ubuntu-noble \
  --disk-format qcow2 --container-format bare \
  --file ~/images/trove-guest-ubuntu-noble.qcow2 \
  --property hw_rng_model=virtio \
  --tag trove
```

**3. `docker_image` の設定**（Trove の mysql マネージャの `docker_image`
デフォルトは `mysql`（Docker Hub 公式イメージ）だが、ゲストに配布される
`trove-guestagent.conf` の実ファイルに `[mysql]` セクションが無いと
`crudini` が値を読めず失敗する。kolla のカスタム設定で明示的に追加する）:

```bash
mkdir -p /etc/kolla/config
cat >> /etc/kolla/config/trove-guestagent.conf <<'EOF'

[mysql]
docker_image = mysql
EOF

kolla-ansible reconfigure -i multinode --tags trove,loadbalancer
```

**4. データストア・バージョンの登録**（`trove_api` コンテナ内で
`trove-manage` を実行。引数の順序は
`datastore_version_update <datastore> <version_name> <manager> <image_id> <packages> <active> [--image-tags TAG]`。
`manager` はデータストア種別と同じ文字列(`mysql`)、`image_id` は空文字にして
`--image-tags trove` で 2 で付けたタグから自動解決させる）:

```bash
docker exec -it trove_api trove-manage datastore_update mysql ""
docker exec -it trove_api trove-manage datastore_version_update \
  mysql 8.0 mysql "" "" 1 --image-tags trove
docker exec -it trove_api trove-manage datastore_update mysql 8.0
```

`trove-manage datastore_version_update --help`（コンテナ内で実行）で
引数を再確認できる。

**検証:**

```bash
# Keystone に database サービスが登録されていること
openstack catalog list | grep database

# python-troveclient（openstack CLI の database プラグイン）が無い場合は追加。
# kolla-venv とは別の軽量 venv に入れるのが安全
python3 -m venv /root/trove-client-venv
/root/trove-client-venv/bin/pip install python-openstackclient python-troveclient
source /etc/kolla/admin-openrc.sh

# サブコマンドに "database" プレフィックスは付かない点に注意
/root/trove-client-venv/bin/openstack datastore list
/root/trove-client-venv/bin/openstack datastore version list mysql
/root/trove-client-venv/bin/openstack database instance list
```

### 5-6. エンドツーエンド確認（2026-09-05 実施・完了）

実際にインスタンスを作成し、ゲスト VM 起動 → Docker で MySQL コンテナ起動 →
control plane への状態報告、まで一通り動くことを確認した。

```bash
openstack network list   # プロジェクトのネットワーク ID を確認

/root/trove-client-venv/bin/openstack database instance create test-mysql-01 \
  --flavor m1.small \
  --size 1 \
  --datastore mysql --datastore-version 8.0 \
  --nic net-id=<プロジェクトネットワークID>

# 数分待つと status が BUILD → ACTIVE、operating_status が HEALTHY になる
watch -n 10 /root/trove-client-venv/bin/openstack database instance show test-mysql-01

# 確認後は削除
/root/trove-client-venv/bin/openstack database instance delete test-mysql-01
```

> **実機の罠**: `--flavor m1.tiny`（disk=1GB）だと
> `Flavor's disk is too small for requested image` で instance-create 自体が
> `ERROR` になる。ゲストイメージのファイルサイズ（このビルドでは約1.4GB）
> より disk が大きい flavor（`m1.small`＝20GB 以上）を使うこと。
> `modules/lc-db` の `var.flavor` にも同じ制約が当てはまる
> （`terraform/modules/lc-db/README.md` 参照）。

`modules/lc-db` 側（Terraform）は、上記のデータストア登録が終わった後の
「プロジェクトが Trove インスタンスを作る」部分のみを扱う。

---

## Phase 6・7

Phase 6（Middleware API）・Phase 7（GitOps）は `16-implementation-phases.md` の
各フェーズ説明を参照してください。
CloudKitty（billing）の実装方針が確定し次第、Phase 6 の billing/ モジュールを追加します。

---

## トラブルシューティング

### terraform init が失敗する（backend 接続エラー）

```bash
# Ceph RGW が起動しているか確認
curl https://s3.lc-cloud.example.internal

# バケットが存在するか確認
aws s3 ls --endpoint-url https://s3.lc-cloud.example.internal

# 開発中は -backend=false で逃げる
terraform init -backend=false
```

### OpenStack 認証が失敗する

```bash
# Application Credential が有効か確認
openstack token issue

# GitHub Secret に正しい値が入っているか確認
# （apply ログの OS_APPLICATION_CREDENTIAL_ID をチェック）
```

### idp-infra: cloud-init で Docker が起動しない（Rocky/EL10）

`journalctl -u docker.service` に以下が出る場合:

- `Unable to find a match: docker-ce docker-ce-cli` … Docker CE の EL10 RPM が
  まだ無い。`idp-infra` の cloud-init は EL9 pinned repo
  (`download.docker.com/linux/centos/9/x86_64/stable`) で回避済み。
- `addrtype ... missing kernel module` / `RULE_APPEND failed` … EL10 GenericCloud に
  `kernel-modules-extra`（`xt_addrtype`）が無い。`/etc/docker/daemon.json` の
  `"firewall-backend": "nftables"` で iptables 経路を使わず回避。
- `IPv4 forwarding is disabled` … `/etc/sysctl.d/99-docker-forward.conf` で
  `net.ipv4.ip_forward=1` を設定（cloud-init が投入済み。手動時は `sysctl --system`）。

VM を作り直すには `terraform apply -replace=openstack_compute_instance_v2.authentik`。

### Authentik から Keystone に認証できない

Keystone の federation mapping が未設定の可能性があります。
OpenStack 管理者に以下の設定を依頼します:

```bash
# Keystone 側での設定（OpenStack 管理者が実行）
openstack federation idp create authentik \
  --remote-id https://auth.lc-cloud.example.internal/application/o/lc-cloud/

openstack federation protocol create openid \
  --identity-provider authentik \
  --mapping lc-cloud-mapping
```

mapping の内容は `04-idp.md`「LC-Cloud へのユーザー同期」セクションを参照してください。
