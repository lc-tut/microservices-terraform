# 実装フェーズ

全コンポーネントの実装順序と、各フェーズの目標・前提条件・成果物を定義します。

---

## フェーズ概要

```text
Phase 0  ローカル開発環境          ✅
Phase 1  GitHub / CI 基盤
Phase 2  Authentik（IdP）
Phase 3  OpenStack platform          ✅
Phase 4  catalog（billing / teams / projects）
Phase 5  workspace モジュール
Phase 6  Middleware API
Phase 7  GitOps
Phase 8  DNS（Designate）
Phase 9  共有 Ingress / LB（Octavia）
```

Phase 8・9 は、実機 Polaris の Service Catalog に Designate・Octavia が
まだ存在しないため後回しにしている（`## Phase 8`・`## Phase 9` の備考参照）。
導入され次第、番号に関わらず着手してよい。

フェーズ間の依存関係:

```text
Phase 0
  └─ Phase 1（GitHub・CI 基盤）
       └─ Phase 2（Authentik）
            └─ Phase 3（OpenStack platform）
                 └─ Phase 4（catalog）
                      ├─ Phase 5（workspace modules）
                      │    └─ Phase 8（DNS）
                      │         └─ Phase 9（共有 Ingress / LB）
                      └─ Phase 6（Middleware API）
                           └─ Phase 7（GitOps）
```

---

## Phase 0 — ローカル開発環境 ✅

**目標**: 本番環境なしで Terraform コードを開発・動作確認できる環境を整える。

**成果物**:

| 項目 | 状態 |
| --- | --- |
| GCP DevStack + Harbor VM（`local/gcp-devstack/`、Terraform管理） | ✅ |
| `local/clouds.yaml` + `OS_CLIENT_CONFIG_FILE` 設定（IAP トンネル経由） | ✅ |
| Authentik Docker Compose (`local/authentik/`) | ✅ |
| kind ローカル K8s クラスター | ✅ |
| VM アイドル自動停止（idle-shutdown systemd タイマー） | ✅ |
| `local/start.sh` で一括起動 | ✅ |

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

### Phase 2 拡張 — メンバーライフサイクル（卒業・OB/OG・年次継続）✅

設計は `documents/authentik/`、実装はローカル Authentik（`local/authentik/`）で動作確認済み。

- `active` / `ob-og` / `alumni` の3層モデル。`ob-og`/`alumni` は Git 上で匿名化
  （`lcn_xxxxxx` 以外の本人特定情報を暗号化）
- 年次継続確認フロー（`annual_renewal.tf`）: Q1（全員）・Q2（卒業年度コホート: OB/OG・連絡不要・留年）を
  `radio-button-group` の実選択肢として実装。`placeholder_expression` を使った choices の与え方、
  `re_evaluate_policies` による Q2 回答後の Stage 再評価など、実機検証で判明した Authentik の
  挙動を反映済み
- 本名・個人連絡先登録（`policy_contact_info.tf`）: 大学ドメイン拒否・電話番号形式バリデーション
- `lcn_id` / `grad_year` を Authentik user attribute として明示的に保持
- GitHub Org: `ob-og` / `alumni` 専用チームを新設（`terraform/platform/github/teams.tf`）。
  Org からは削除せず、所属チーム切り替えでアクセスを絞る
- enrollment に GitHub/Discord 連携の推奨案内 Stage を追加（`authentik_stage_source` は
  Enterprise 限定と確認済みのため、静的案内 Stage で代替）
- Brand（ロゴ・favicon・背景画像）を `assets/` 配下の画像から raw.githubusercontent.com 経由で設定
- Discord OAuth Source（`provider_discord_source.tf`）: アカウント紐づけ専用（ログインには使わない）。実装済み
- ログイン画面のカスタマイズ（`authentication.tf`）: 組み込み `default-authentication-flow` は
  blueprint 管理で上書きされるため、独自の authentication flow を新設してタイトル・背景を差し替え
- `recovery.tf` を「初回 welcome」と「パスワードリセット」で出し分け: `has_usable_password()`
  が False（未設定）なら welcome 案内 + identification スキップ、設定済みなら通常のリセット動線。
  welcome メールは `Accept-Language: ja` を付けて送信し、同梱の `ja_JP` 翻訳カタログで件名・本文を
  日本語化。実機検証済み（2026-08-25）

**未実装（別途）**: Discord Bot 本体。
`stage_configuration` フローをログイン中に自動で割り込ませる配線方法は未確定。

---

## Phase 3 — OpenStack platform ✅

**目標**: 全プロジェクトが共有する OpenStack のネットワーク基盤・クォータ定義を整える。

**前提条件**:

- Phase 1 の CI が動作していること
- `LC_CLOUD_APP_CRED_ID` / `LC_CLOUD_APP_CRED_SECRET` が GitHub Secrets に登録済みであること

**作業内容**:

1. `terraform/platform/openstack/network/` の実装 ✅ 実装・本番適用・実機検証済み。
   実機確認の結果、想定と異なり VPC Gateway に相当する router
   （`lc-dev-router`）と、外部ネットワークの共有を実現する RBAC ポリシー
   （`access_as_external`）が共に既に存在していたため、新規作成ではなく
   `terraform import` で両方を管理下に置いた（実インフラへの変更なし）。
   `subnetpool`（新規追加分）のみ実際に apply 済み。`terraform plan` clean 確認済み
   - `gateway.tf` — VPC Gateway ルーター（既存 `lc-dev-router` を import）
   - `subnetpool.tf` — IP 帯域マスタープール（`10.0.0.0/8`、/24 固定払い出し、
     `shared = true`）。既存の手動作成サブネット（`10.10.0.0/24`、この pool 外）
     との衝突可能性は極めて低いことを確認済み（コメント参照）
   - `external_network.tf` — 外部ネットワークは data 参照のみ。ただし
     shared 属性ではなく RBAC ポリシーで全プロジェクト共有されていたため、
     そのポリシーを import して管理下に置いた

1. `terraform/platform/openstack/images/` の実装 ✅ 実装・本番適用・実機検証済み
   - Ubuntu 24.04 公式 cloud image を Glance に登録（`web_download` で URL から
     直接インポート）。この repo にはまだ Packer 等のイメージビルドパイプラインが
     無いため、「SSH CA 組み込み済み」は厳密にはイメージファイルへの焼き込み
     ではなく、CA 鍵ペア（`ssh_ca.tf`）を生成して公開鍵をイメージの
     properties と Terraform output の両方に持たせる形にとどめている。
     実際に VM 起動時 sshd へ `TrustedUserCAKeys` を設定するのは
     Phase 5 `modules/lc-vm` 側の cloud-init の責務（未実装）
   - CA 秘密鍵は state にのみ保持し、証明書発行用の CLI（Phase 6
     Middleware API）以外には渡さない設計

1. `terraform/platform/openstack/quotas/` の実装 ✅ 実装・本番適用・実機検証済み
   （Nova・Cinder 双方の quota-class-set API）。Cinder API の URL に project_id
   を含めると 400 になる実機特有の罠を発見・修正。詳細は
   `terraform/platform/openstack/quotas/README.md` 参照
   - クォータティア定義（small / medium / large）
   - `07-quota.md` の設計に従い実装

**成果物**: `catalog/projects/` が subnetpool から /24 を払い出せる状態。
Phase 3 の3項目（network・images・quotas）は全て実装・実機適用済み。

---

## Phase 4 — catalog

**目標**: チーム・プロジェクトの登録を PR ベースで処理できる仕組みを完成させる。

**前提条件**:

- Phase 3 完了（subnetpool・VPC gateway が存在すること）

**作業内容**:

1. `terraform/catalog/teams/_template/` 実装 ✅
   - `authentik.tf` — Authentik グループ
   - `lc_cloud.tf` — `openstack_identity_project_v3`（Keystone project）+
     `modules/lc-cloud-quota`。自動化アカウントへの `member` ロール付与も
     ここで行う（`catalog/projects/` が Application Credential を
     セルフサービス発行するために必要。README 参照）
   - `outputs.tf` — `openstack_project_id`・`authentik_group_id`

1. `terraform/catalog/projects/_template/` 実装 ✅
   - `lc_cloud.tf` — ネットワーク・Subnet（`platform/openstack/network/` の
     subnetpool から）・Router Interface・Application Credential
     （Access Rules 付き、`team_project_id` にスコープしなおした provider で発行）
   - GitHub Actions Secret への自動登録は未実装（意図的に保留。下記参照）

1. `terraform/catalog/billing-accounts/` テンプレート実装 ✅
   - `personal/_template/`・`teams/_template/` — クォータ上書きのみ
     （デフォルトから変更する場合のみ使う。`08-billing.md` 参照）
   - CloudKitty との連携（予算・通知）は未実装（下記参照）

**成果物**: `_template` をコピーして PR を出すだけで
OpenStack プロジェクト・ネットワーク・Application Credential が払い出される状態。
`terraform validate` は全 template で確認済み。**`catalog/teams/`・
`catalog/projects/` は実機 Polaris でエンドツーエンド検証済み**
（`sandbox-test` という名前でチーム・プロジェクトを実際に作成し、
Keystone project・role assignment・Authentik Group・クォータ3種・
network/subnet/router interface・Application Credential が全て実際に
作られたことを `openstack`/Authentik API で確認した上で `terraform destroy`
して削除。2026-09-04）。`terraform/catalog/billing-accounts/` は
（前提となる team/project の apply 後に）同様に動作する見込みだが、
個別には検証していない。

> **実装できなかった／意図的に保留した部分**（設計文書との差分。詳細は各
> `_template/README.md`・`[P3]`・`[P10]` 参照）:
> - **GitHub Actions Secret への自動登録**: `workspaces/` を CI/CD apply する
>   仕組みがまだ整備できていないため保留。Application Credential は
>   state にのみ保存し、`terraform output -raw app_cred_secret` で手動取得する。
>   GitHub Actions 側の CI/CD 整備後に `github_actions_secret` を追加する。
> - **「Organization」（予算上限・Credit 残高）**: Keystone にも CloudKitty
>   にも存在しない独自概念で、Middleware API 側の自前実装が要る（未着手）。
>   `catalog/teams/`・`catalog/billing-accounts/` は素の Keystone project +
>   クォータのみを扱い、予算・Credit 残高は扱わない。
> - **個人 OpenStack project の自動作成**: `platform/members/` にまだ実装が
>   無い。`catalog/billing-accounts/personal/_template/` は対応する project が
>   存在する前提で動くため、現状は使えない（前提が整うまでの先行実装）。
> - **DNS Zone・LB Pool**: Designate・Octavia とも実機 Polaris 未導入のため
>   Phase 8・Phase 9 に切り出した（`[P10]`）。
> - **Harbor Project 連携**: `terraform/platform/harbor/` で Harbor 本体の
>   OIDC 設定は実装済みだが、プロジェクト単位の Harbor Project 自動作成は未実装。

> DNS Zone・LB Pool はこの Phase では作らない。個別プロジェクトが自分の
> LB・floating IP を持つ設計は `12-openstack-resources.md`／`07-quota.md`
> の「独自 LB 作成禁止・`services.loadbalancers = 0` 強制」方針と矛盾するため
> 廃止した（[P10] 参照）。DNS は Phase 8、外部公開の実体（共有 Ingress
> Controller + 1 個の Octavia LB）は Phase 9 で扱う。

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

## Phase 8 — DNS（Designate）

**目標**: プロジェクトのアプリに人間が読めるホスト名を割り当てられるようにする。

**前提条件**:

- 実機 Polaris に Designate サービスが導入されていること
- Phase 4 完了

**作業内容**:

1. Designate 導入状況の確認・インフラ担当への導入依頼
1. `terraform/catalog/projects/_template/` に `openstack_dns_zone_v2` を追加
1. `modules/lc-dns-record`（Phase 5 で予定）との連携確認

**成果物**: プロジェクトごとに `<project>.lc-cloud.example.` ゾーンが自動払い出しされる状態。

> **備考**: 実機 Polaris の Service Catalog には現時点（2026-09-04 確認）で
> Designate が存在しない（`openstack catalog list` の結果は
> cloudkitty・heat・placement・keystone・glance・neutron・cinder・nova・heat-cfn
> のみ）。導入時期未定のため、実装は Designate が使えるようになってから着手する。

---

## Phase 9 — 共有 Ingress / LB（Octavia）

**目標**: OpenStack VM アプリ・k8s アプリの両方を、1 個の共有 Octavia LB +
k8s Ingress Controller に集約して外部公開する。プロジェクトごとの個別 LB
作成は行わない。

**前提条件**:

- 実機 Polaris に Octavia サービスが導入されていること
- Phase 5 完了（k8s クラスターが存在すること）
- Phase 8（DNS）— ホスト名ベースのルーティングを使うなら実質必須

**設計方針（決定事項、詳細は [P10] 参照）**:

- Octavia LB は全体で 1 個のみ。k8s の `ingress-nginx` Controller の
  Service（`type=LoadBalancer`）がそれを払い出す。プロジェクト単位で
  LB Pool を作ることはしない（`07-quota.md` の
  `services.loadbalancers = 0` 強制・`12-openstack-resources.md` の
  「独自 LB 作成禁止」に準拠）。
- k8s アプリ: k8s `Ingress` リソース経由でそのまま共有 Controller に乗る。
- OpenStack VM（k8s を使わないプロジェクト）: VM の internal IP を
  selector 無し + 手動 `Endpoints` の headless Service として登録し、
  同じ Ingress 経由でルーティングする。個別 floating IP・LB は持たない。
- 管理用 API（infra-api・k8s-api、`14-middleware-architecture.md`）も
  同じ共有 Controller に相乗りし、path（`/api/infra/*`・`/api/k8s/*`）と
  Authentik の JWT 検証で権限を分離する。管理用・ユーザー用で LB を
  物理的に分けることはしない。

**作業内容**:

1. Octavia 導入状況の確認
1. k8s クラスターに `ingress-nginx` をデプロイし、
   `Service type=LoadBalancer` で Octavia LB を払い出す
1. OpenStack VM プロジェクト向け headless Service + `Endpoints` 払い出し
   手順の整備（`modules/lc-vm` または新規モジュール）
1. `catalog/projects/_template` からの DNS recordset 連携

**成果物**: プロジェクトが個別に LB・floating IP を意識せず、
ホスト名を割り当てるだけで外部公開できる状態。

> **備考**: 実機 Polaris の Service Catalog には Octavia も現時点で
> 存在しない。Designate 同様、導入され次第着手する。

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

**（訂正・2026-09-04）**: 実装時、間に挟む `modules/lc-cloud-organization/`
モジュール自体を作らず、`catalog/teams/_template/lc_cloud.tf` に
`openstack_identity_project_v3` + `module "quota"`（`modules/lc-cloud-quota`）を
直接書く形にした（ラッパーを1層挟む意味が薄いため）。「Organization」という
予算・Credit 残高を持つ独自概念は元々別の課題（Middleware API 側の自前実装、
未着手）であり、この module 云々とは無関係。詳細は
`terraform/catalog/teams/_template/lc_cloud.tf` のコメント参照。

**[P4] Harbor → `enable_harbor` フラグで後から追加**

Harbor は提供予定だが構築タイミングが未定のため、
`catalog/projects/_template/harbor.tf` に `count = var.enable_harbor ? 1 : 0` を追加する。

**（進捗・2026-09-04）**: Harbor 本体（`terraform/platform/infra/harbor-infra/`、
実機適用済み）と Authentik OIDC 連携（`terraform/platform/harbor/`）は実装済み。
`catalog/projects/_template/harbor.tf`（プロジェクト単位の Harbor Project 自動作成、
`enable_harbor` フラグ）はまだ未実装。
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

**[P10] プロジェクト単位 LB Pool 廃止 → 共有 Ingress Controller 1 本に統一（2026-09-04）**

`05-project-lifecycle.md` の `catalog/projects/_template/lc_cloud.tf` は
プロジェクトごとに `openstack_lb_pool_v2.http` を作る例を示していたが、
これは `07-quota.md`（全 tier で `services.loadbalancers = 0` 強制）・
`12-openstack-resources.md`（「独自 LB の作成は禁止。K8s アプリは
Kubernetes Ingress Controller 経由」）と矛盾していた。後者の方が新しく
詳細な設計のため、そちらを正とし前者の記述は削除する。

正しい設計は「Octavia LB は LC-Cloud 全体で 1 個のみ。k8s の共有
`ingress-nginx` Controller がそれを払い出し、k8s アプリはもちろん、
k8s を使わない OpenStack VM アプリも headless Service 経由で同じ
Controller に相乗りする」という一本化。管理用 API
（infra-api・k8s-api）も同じ Controller に乗り、LB を物理的に分けず
path・JWT 認証で権限を分離する（VM・k8s それぞれに別の LB を用意する
「LB の LB」構成にはしない）。

DNS Zone（Designate）・共有 Ingress/LB（Octavia）はいずれも実機 Polaris
にサービス自体が存在しないため、Phase 4 のスコープから外し、
Phase 8・Phase 9 として後回しにした。詳細は該当フェーズの節を参照。

---

### 🟡 保留中

*保留中の項目はありません。*

---

### ✅ 追加解決済み

**[P5] CloudKitty の導入方針 → restapi プロバイダーで IaC 管理 ✅ 実装・実機検証済み**

CloudKitty を OpenStack に追加し、Hashmap ルールを `Mastercard/terraform-provider-restapi` で
管理する方針で実装。複数の実 OpenStack 環境で `terraform apply` 成功・`terraform plan`
clean・CloudKitty API での実データ確認まで完了済み（`terraform/platform/openstack/cloudkitty/`・
`terraform/modules/cloudkitty-service/`）。CloudKitty 本体（VM・コンテナ）のプロビジョニングは
`terraform/platform/infra/cloudkitty-infra/`。

- **API**: Hashmap エンドポイントは CRUD が REST で完結しており、IaC 管理に適している
- **プロバイダー**: `restapi_object` + `id_attribute`（`service_id`/`field_id`/`mapping_id`）で対応
- **UPDATE 問題（訂正）**: 当初「PUT が 302 を返す」と想定していたが、実機検証の結果
  **PUT は 405 Method Not Allowed**（services/fields/mappings いずれも更新不可）だった。
  `force_new` で destroy → create にする対処自体は同じ
- **その他、実機検証で判明した罠**（API パスの組み立て方・JSON フィールド名の実際・
  `ignore_server_additions` が必須な理由）は `terraform/modules/cloudkitty-service/main.tf`
  のコメントにまとめてある
- **モジュール化**: `modules/cloudkitty-service` として `service → field → mappings` を抽象化。
  2 モード:
  - **field モード**（`field_name != null`）: field の値ごとの mapping（`mappings`）。
    例: `field_name = "flavor_id"` でフレーバー別単価。
  - **service-level flat モード**（`field_name = null`）: service 直付けの単一 flat/rate
    mapping（`service_rate`）。`09-costs.md` の vCPU/RAM/Block/Floating IP はこちら
    （collector が既にプロジェクト単位の使用量そのものを qty として返すため、
    field で値をマッチングする必要がない）。

```hcl
# terraform/platform/openstack/cloudkitty/main.tf
# service 名は collector 側のメトリクス名と一致させる。
module "vcpu" {
  source       = "../../../modules/cloudkitty-service"
  service_name = "vcpu"
  service_rate = { cost = "1.000000", type = "flat" } # 1 Credit / vCPU-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}
# 同様に memory=0.25 / volume=0.002 / floating_ip=0.5
```

**OpenStack 側の collector 選定について**: CloudKitty は Gnocchi collector
（Ceilometer 経由でメータリングする、OpenStack の標準構成）と Prometheus collector
（外部の openstack-exporter が API を読み取るだけでメータリングする構成）のいずれかを
選べる。コントロールプレーン側で Ceilometer の通知パイプラインが有効化されていない・
あるいはコントロールプレーンには手を入れたくない環境では Prometheus collector が
現実的な選択肢になる（openstack-exporter → Prometheus の recording rule で
`project_id` 単位の系列へ正規化 → CloudKitty が `<metric>{project_id="<id>"}[period]`
形式でクエリ、の経路。Hashmap ルール自体は collector 非依存で、service 名を
collector 側のメトリクス名に合わせるだけで両方式を行き来できる）。
実際にどちらを採用したか・具体的な構成は環境ごとに異なるため
`terraform/platform/infra/cloudkitty-infra/README.md` を参照。

**Kubernetes（namespace 単位）のコスト管理について**: CloudKitty の `collector` と
`scope_attribute` はいずれも1インスタンスにつき1つしか設定できないため、
OpenStack 用と Kubernetes 用（`auth_strategy=noauth`・`scope_attribute=namespace`・
kube-state-metrics 連携）で **別インスタンス**として構築する方針。両者とも `09-costs.md` の
Credit 建て単価で計算することで、インスタンスは分かれていても同じ物差しで数字が出る。
K8s 用インスタンスの実装はこれから（未着手・今回のスコープ外）。

**未着手（別課題）**: 複数の CloudKitty インスタンス（OpenStack用・K8s用）の計算結果を
「請求アカウント（Organization）」単位で合算し、予算と比較する仕組み。これは CloudKitty にも
OpenStack 標準機能にも存在せず、まるごと自前実装が必要（Middleware API 側の実装課題として
持ち越し。詳細は `08-billing.md`・`09-costs.md` の該当注記を参照）。

実装タイミング: Phase 3（OpenStack platform）の一部として `terraform/platform/openstack/cloudkitty/`
を追加。複数の実 OpenStack 環境で実機適用・`plan` clean 確認済み。
基盤の構築手順は `terraform/platform/infra/cloudkitty-infra/README.md`。

**基盤の Terraform 化・Prometheus 分離 ✅ 完了（2026-09-04）**: CloudKitty 本体
（`terraform/platform/infra/cloudkitty-infra/`）と Prometheus+exporter
（`terraform/platform/infra/prometheus-infra/`、他の監視用途にも再利用できるよう
独立した VM に分離）を、それぞれ `idp-infra` と同じ cloud-init ベースの
Terraform root として実装。従来手動構築だった CloudKitty VM は
`terraform import` で無停止のまま管理下に移行し、稼働中のまま
Prometheus/exporter コンテナを停止・削除して新しい別 VM の Prometheus を
参照するよう再設定した（実インフラは継続稼働・課金データ無影響）。
実機で判明した罠（`tls_private_key` が import 非対応・`random_password` の
`special` 属性・`security_group_rule` の `description` が force-new・
Rocky Linux の `cockpit.socket` が既定でポート 9090 を握っている等）は
`infra/idp-infra/README.md`・`infra/cloudkitty-infra/README.md`・
`infra/prometheus-infra/README.md` にそれぞれ記録。

**`idp/`・`members/`・`github/` の実機初回適用 ✅ 完了（2026-09-04）**:
本番相当の実 Authentik（`idp/` 70+ リソース・SMTP・GitHub/Discord Source）、
実メンバー1名の Authentik アカウント作成と入会メール送信（`members/`、実際に
本人が受信してアカウント設定を完了するところまで確認）、実 `lc-tut`
Organization の team 7件・branch protection・CODEOWNERS（`github/`、
push 許可の実効性まで GraphQL で確認）を、それぞれ実機に対して適用・検証済み。
過程で見つけた実バグ（`authentik_stage_prompt_field` の `sub_text` 末尾改行が
永久 drift になる、`authentik_source_oauth.github` の `oidc_jwks_url` が
サーバー側デフォルトで埋まる、`authentik_user.is_active` が
`ignore_changes` に無く本人のアカウント有効化を巻き戻してしまう、
`github_branch_protection` の `push_allowances` は対象チームに
`github_team_repository` で何らかのリポジトリアクセス権を与えていないと
サイレントに無視される）はいずれも該当 `.tf` のコメントとして残してある。

> **重要**: 上記3つ（`idp/`・`members/`・`github/`）はいずれも、本番の
> Ceph RGW backend ではなく `backend_override.tf` によるローカル state で
> 検証・適用した（本番 backend の認証情報がこの検証環境に無いため。
> `infra/idp-infra/README.md`「本番 Ceph RGW backend への適用時の注意」と
> 同じ事情）。**実際の Authentik・GitHub 側には反映済みだが、本番 Ceph RGW
> 上の state はこれらの変更を一切知らない。** 次に CI（本番 backend）から
> apply すると、特に `github/` は「name must be unique」等で失敗し、
> `idp/`・`members/` は空の state から重複作成を試みる。本番運用に戻す前に、
> ローカルで作った state を本番 backend へ移す（`terraform state push` 等）か、
> 同じ手順で改めて import し直す必要がある。
