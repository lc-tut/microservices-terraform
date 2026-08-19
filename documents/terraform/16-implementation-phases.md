# 実装フェーズ

全コンポーネントの実装順序と、各フェーズの目標・前提条件・成果物を定義します。

---

## フェーズ概要

```text
Phase 0  ローカル開発環境          🚧 GCP 移行中
Phase 1  GitHub / CI 基盤
Phase 2  Authentik（IdP）
Phase 3  OpenStack platform
Phase 4  catalog（billing / teams / projects）
Phase 5  workspace モジュール
Phase 6  Middleware API
Phase 7  GitOps
```

フェーズ間の依存関係:

```text
Phase 0
  └─ Phase 1（GitHub・CI 基盤）
       └─ Phase 2（Authentik）
            └─ Phase 3（OpenStack platform）
                 └─ Phase 4（catalog）
                      ├─ Phase 5（workspace modules）
                      └─ Phase 6（Middleware API）
                           └─ Phase 7（GitOps）
```

---

## Phase 0 — ローカル開発環境 🚧

**目標**: 本番環境なしで Terraform コードを開発・動作確認できる環境を整える。

**成果物**:

| 項目 | 状態 |
| --- | --- |
| GCP DevStack + Harbor VM（`local/gcp-devstack/`、Terraform管理） | 要セットアップ |
| `local/clouds.yaml` + `OS_CLIENT_CONFIG_FILE` 設定（IAP トンネル経由） | 要セットアップ |
| Authentik Docker Compose (`local/authentik/`) | ✅ |
| kind ローカル K8s クラスター | 要セットアップ |
| Vault dev モード | 要セットアップ |
| `local/start.sh` で一括起動 | ✅ |
| Windows 自動停止タスク（`windows-autostop/`） | 要セットアップ |

詳細は `15-local-development.md` を参照。

---

## Phase 1 — GitHub / CI 基盤

**目標**: PR ベースの Terraform apply を自動化するパイプラインを整える。
以降のフェーズはすべてこの CI を通じてデプロイする。

**前提条件**:

- GitHub Organization が存在すること

**作業内容**:

1. **GitHub Secrets のセットアップ**（手動）
   - Organization または Repository Secrets に以下を登録:
     - `AUTHENTIK_TOKEN` — Authentik API トークン
     - `LC_CLOUD_APP_CRED_ID` — OpenStack App Credential ID（admin 相当）
     - `LC_CLOUD_APP_CRED_SECRET` — OpenStack App Credential Secret
     - `SOPS_AGE_KEY` — SOPS 復号キー

1. **State バックエンドのセットアップ**（手動）
   - Ceph RGW に `linuxclub-tfstate` バケットを作成

1. **GitHub Organization の設定**（手動）
   - Branch Protection の有効化
   - `circle-admin` チームの作成

1. **GitHub Actions ワークフロー実装**（Terraform 外・直接コミット）
   - `.github/workflows/plan.yml`
   - `.github/workflows/apply.yml`
   - `.github/workflows/modules-check.yml`
   - `.github/workflows/codeowners-check.yml`

1. **`terraform/platform/github/` の初期実装**（最初は手動 apply）
   - GitHub Teams 定義
   - Branch Protection（Terraform 管理に移行）

**成果物**: PR を出すと plan が走り、merge すると apply される状態。

---

## Phase 2 — Authentik（IdP）

**目標**: メンバー管理・SSO の基盤となる IdP を Terraform で管理する。

**前提条件**:

- Phase 1 の CI が動作していること
- Authentik 本番インスタンスが LC-Cloud 上で稼働していること
- `AUTHENTIK_TOKEN` が GitHub Secrets に登録済みであること

**作業内容**:

1. `terraform/platform/idp/` の実装
   - `flows/enrollment.tf` — 入会フロー
   - `flows/recovery.tf` — パスワードリセット
   - `policies/username.tf` — username バリデーション
   - `providers/lc_cloud.tf` — LC-Cloud OIDC プロバイダ（Keystone フェデレーション用）
   - `providers/github_source.tf` — GitHub OAuth Source（任意連携）
   - `notifications/` — enrollment 完了 Webhook・GitHub 連携 Webhook

1. `terraform/platform/members/` の基本構造確立
   - `active/grad-XXXX/` ディレクトリ構成
   - SOPS 暗号化キーの配布（age）

**成果物**: Authentik で入会フローが機能し、メンバーが username を自己設定できる状態。

---

## Phase 3 — OpenStack platform

**目標**: 全プロジェクトが共有する OpenStack のネットワーク基盤・クォータ定義を整える。

**前提条件**:

- Phase 1 の CI が動作していること
- `LC_CLOUD_APP_CRED_ID` / `LC_CLOUD_APP_CRED_SECRET` が GitHub Secrets に登録済みであること

**作業内容**:

1. `terraform/platform/network/` の実装
   - `gateway.tf` — VPC Gateway ルーター
   - `subnetpool.tf` — IP 帯域マスタープール（例: `10.0.0.0/8`）
   - `external_network.tf` — 外部ネットワーク・RBAC

1. `terraform/platform/images/` の実装
   - SSH CA 組み込み済みの Ubuntu 24.04 ベースイメージ管理

1. `terraform/platform/quotas/` の実装
   - クォータティア定義（small / medium / large）
   - `07-quota.md` の設計に従い実装

**成果物**: `catalog/projects/` が subnetpool から /24 を払い出せる状態。

---

## Phase 4 — catalog

**目標**: チーム・プロジェクトの登録を PR ベースで処理できる仕組みを完成させる。

**前提条件**:

- Phase 3 完了（subnetpool・VPC gateway が存在すること）

**作業内容**:

1. `terraform/catalog/billing-accounts/` テンプレート実装
   - `personal/_template/`
   - `teams/_template/`
   - CloudKitty との連携（予算・通知）

1. `terraform/catalog/teams/` テンプレート実装
   - `_template/authentik.tf` — Authentik グループ
   - `_template/outputs.tf` — `organization_id` を公開

1. `terraform/catalog/projects/` テンプレート実装
   - `_template/lc_cloud.tf` — ネットワーク・Subnet・Router Interface・DNS Zone
   - Application Credential（Access Rules 付き）の発行
   - GitHub Actions Secret への自動登録（`github_actions_secret` リソース）
   - `_template/harbor.tf` — Harbor プロジェクト + RBAC

**成果物**: `_template` をコピーして PR を出すだけで
OpenStack プロジェクト・ネットワーク・Application Credential が払い出される状態。

---

## Phase 5 — workspace モジュール

**目標**: プロジェクトオーナーが自由にインフラを定義できる再利用可能モジュールを提供する。

**前提条件**:

- Phase 4 完了（catalog が Application Credential を発行できること）

**作業内容**:

1. `terraform/modules/` の実装（優先度順）

   | モジュール | 内容 |
   | --- | --- |
   | `lc-vm` | VM + ボリューム + SG |
   | `lc-dns-record` | DNS レコード（ゾーンを data で自動参照） |
   | `lc-k8s-app` | K8s PVC + Secret + ConfigMap |
   | `lc-object-bucket` | Swift コンテナ + CORS / lifecycle |
   | `lc-db` | Trove DB インスタンス + ユーザー |
   | `authentik-user` | Authentik ユーザー作成 |
   | `authentik-group` | Authentik グループ作成 |

1. `terraform/workspaces/` のテンプレート整備

**成果物**: プロジェクトオーナーが `module "app" { source = "../../modules/lc-vm" }` と書ける状態。

---

## Phase 6 — Middleware API

**目標**: GUI・運用ツールが叩く REST API を実装・デプロイする。

**前提条件**:

- Phase 4 完了（各プロジェクトの Application Credential が GitHub Secrets に登録済みであること）
- `lc-platform` Namespace が K8s に存在すること
- Ingress Controller（Traefik / Nginx）がデプロイ済みであること

**作業内容**:

1. **infra-api** の実装（Go / Python / その他）
   - `auth/` — OIDC コールバック・JWT 検証
   - `compute/` — Nova
   - `network/` — Neutron・Designate
   - `storage/` — Swift・Manila
   - `database/` — Trove
   - `billing/` — CloudKitty コスト・クォータ申請（→ GitHub PR）
   - `audit/` — Loki 書き込み・検索・Discord 通知

1. **k8s-api** の実装
   - Pod / Deployment / PVC の読み取り
   - `pods/{pod}/logs` SSE
   - `pods/{pod}/exec` WebSocket
   - ClusterRole・ServiceAccount 設定

1. **K8s マニフェスト**（`lc-platform` Namespace）
   - Deployment・Service・Ingress（infra-api / k8s-api）
   - NetworkPolicy

**成果物**: `https://api.lc-cloud.example.internal/api/infra/` が稼働し、
GUI から VM 操作・ログ確認・課金閲覧ができる状態。

詳細は `14-middleware-architecture.md` を参照。

---

## Phase 7 — GitOps

**目標**: アプリケーションのデプロイをチームに委任する仕組みを整える。

**前提条件**:

- Phase 5 完了（workspace で K8s リソースが定義できること）
- ArgoCD / FluxCD が LC-Cloud K8s 上で稼働していること

**作業内容**:

1. ArgoCD / FluxCD のセットアップ
1. プロジェクトごとの `Application` リソース定義テンプレート
1. Workspace の `lc-k8s-app` モジュールとの連携確認

**成果物**: チームが Git にコミットするだけでアプリが K8s にデプロイされる状態。

---

## レビューと決定事項

### ✅ 解決済み

**[P1] CI/CD 認証情報管理 → GitHub Secrets に変更**

Vault は導入せず、GitHub Secrets に直接保存する。
`06-cicd.md` の `vault-action` ステップを削除し、`${{ secrets.* }}` で参照する。
必要な Secrets:

| Secret 名 | 内容 |
| --- | --- |
| `AUTHENTIK_TOKEN` | Authentik API トークン |
| `LC_CLOUD_APP_CRED_ID` | OpenStack Application Credential ID（admin 相当） |
| `LC_CLOUD_APP_CRED_SECRET` | OpenStack Application Credential Secret |
| `SOPS_AGE_KEY` | SOPS 復号キー |
| `HARBOR_ADMIN_PASSWORD` | Harbor 管理者パスワード |
| `LC_CLOUD_APP_CRED_ID_{PROJECT}` | Workspace 用プロジェクト別 Credential（自動登録） |
| `LC_CLOUD_APP_CRED_SECRET_{PROJECT}` | 同上 |

**[P2] Keystone ユーザー同期 → OIDC フェデレーションに変更**

SCIM は標準 Keystone に存在しないため廃止。
Authentik を OIDC IdP として Keystone に連携し、ユーザーをコピーせずに認証する。
`04-idp.md` の `scim/` セクションを削除し、Keystone federation mapping の設定を追加する。

```text
変更前: Authentik → SCIM → Keystone にユーザーレコードをコピー（動かない）
変更後: ユーザーが LC-Cloud にアクセス → Keystone → Authentik で認証
       → Authentik グループ情報を Keystone プロジェクトロールにマッピング
```

**[P3] `lc_cloud_organization` → カスタムモジュールに変更**

`modules/lc-cloud-organization/` モジュールを作成し、内部で
`openstack_identity_project_v3` + クォータ設定を行う。
`catalog/teams/` からは `module "org"` で呼び出す。

**[P4] Harbor → `enable_harbor` フラグで後から追加**

Harbor は提供予定だが構築タイミングが未定のため、
`catalog/projects/_template/harbor.tf` に `count = var.enable_harbor ? 1 : 0` を追加する。
Phase 4 を Harbor 待ちにする必要はない。

**[P6] Phase 1 の手動 apply → circle-admin が担当**

CI 構築前の bootstrap は circle-admin が手元で実行する。
具体的には以下を手動 apply する:

1. `terraform/platform/github/` — Branch Protection・GitHub Teams
1. GitHub Actions ワークフロー（`.github/workflows/`）を直接コミット

以降は CI 経由で apply する。

**[P7] State バックエンド → 開発はローカル、本番は S3**

`backend.tf` は S3 設定を持ちつつ、開発時は `-backend=false` で plan のみ実行する。
本番の S3 エンドポイントが確定したら `backend.tf` の `endpoint` を更新する。

```hcl
# 開発時
terraform init -backend=false
terraform plan

# 本番（S3 エンドポイント確定後）
terraform init
terraform apply
```

**[P8] `01-overview.md` のドキュメント一覧 → 更新済み**

**[P9] `06-cicd.md` の Vault URL → GitHub Secrets 移行に伴い不要**

---

### 🟡 保留中

**[P5] CloudKitty の有無**

billing モジュールの実装方針は CloudKitty の構築方針が決まり次第更新する。
それまで `Phase 6` の billing/ モジュールの実装は後回しにする。
