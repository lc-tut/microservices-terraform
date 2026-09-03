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

#### 現状（最小構成 / 実機検証済み） — `terraform/platform/idp-infra/`

Polaris（実機 OpenStack、Kolla-Ansible）には **Magnum / Octavia が無く**、
マネージド Kubernetes 基盤が存在しない。そのため現状の最小構成は
**単一 VM + Docker Compose** で、`terraform/platform/idp-infra/` が IaC 管理する。

- `rocky-10` / `m1.medium`(4GB/2vCPU) / boot-from-volume 40GB / `lc-dev-net`
- Floating IP を `ext-net` から採番、Security Group で 22 / 9000 / 9443 / ICMP を許可
- cloud-init が Docker を入れ、`local/authentik/docker-compose.yml` を忠実移植した
  構成（**server + worker + postgresql、Redis なし**）を起動する
- `AUTHENTIK_SECRET_KEY` / postgres パスワード / akadmin パスワード / API トークンは
  `random_*` で新規生成し tfstate（MinIO/Ceph S3）にのみ保存

```bash
export OS_CLIENT_CONFIG_FILE=/path/to/local/clouds.yaml   # lc-dev scope の cloud
cd terraform/platform/idp-infra
terraform init && terraform apply

terraform output -raw authentik_url               # → 2-3 の TF_VAR_authentik_url
terraform output -raw authentik_token             # → 2-2 の AUTHENTIK_TOKEN（手動発行不要）
terraform output -raw authentik_akadmin_password  # akadmin Web ログイン用
```

> **食い違い注記**: `## 前提条件` の「LC-Cloud 上に K8s クラスターが存在すること」は
> Polaris 実機ではまだ満たされていない。下記 Helm 手順は将来 K8s 基盤ができた
> 時点の本番像であり、**未検証**。当面は上記 VM 構成で Phase 2 以降を進める。
>
> Rocky/EL10 は 2026 時点で Docker CE の EL10 向け RPM が未提供のため、cloud-init は
> EL9 pinned repo + Docker の nftables firewall backend + `net.ipv4.ip_forward=1` で
> 回避している（`terraform/platform/idp-infra/templates/cloud-init.yaml.tftpl` 参照）。

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
  --body "$(cd terraform/platform/idp-infra && terraform output -raw authentik_token)"
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

### 3-1. `terraform/platform/network/` の apply

VPC Gateway・subnetpool・外部ネットワークを作成します。

```bash
git checkout -b feat/platform-network
# terraform/platform/network/ を実装
git add terraform/platform/network/
git commit -m "feat(network): VPC gateway and subnetpool"
git push && gh pr create ...
# 承認 → merge → apply
```

### 3-2. `terraform/platform/images/` の apply

SSH CA 組み込み済みの Ubuntu 24.04 ベースイメージを登録します。

```bash
git checkout -b feat/platform-images
git add terraform/platform/images/
git commit -m "feat(images): base VM image with SSH CA"
git push && gh pr create ...
```

### 3-3. `terraform/platform/quotas/` の apply

クォータティア（small / medium / large）を定義します。

```bash
git checkout -b feat/platform-quotas
git add terraform/platform/quotas/
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

## Phase 5 以降

Phase 5（workspace モジュール）・Phase 6（Middleware API）・Phase 7（GitOps）は
`16-implementation-phases.md` の各フェーズ説明を参照してください。

Phase 5 以降は Phase 4 完了後に着手します。
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
OpenStack 管理者（Polaris チーム）に以下の設定を依頼します:

```bash
# Keystone 側での設定（OpenStack 管理者が実行）
openstack federation idp create authentik \
  --remote-id https://auth.lc-cloud.example.internal/application/o/lc-cloud/

openstack federation protocol create openid \
  --identity-provider authentik \
  --mapping lc-cloud-mapping
```

mapping の内容は `04-idp.md`「LC-Cloud へのユーザー同期」セクションを参照してください。
