# microservices-terraform

LinuxClub サークルの運営基盤（LC-Cloud）を Terraform で管理するリポジトリです。

## 何を管理しているか

| サービス | 管理内容 |
| --- | --- |
| **Authentik** | メンバーアカウント・グループ・入会フロー・SSO プロバイダ |
| **GitHub** | Organization・Teams・Branch Protection・CODEOWNERS |
| **Harbor** | プロジェクト・RBAC・脆弱性スキャンポリシー |
| **LC-Cloud（OpenStack）** | Organization・クォータ（CPU/Memory/ディスク） |
| **LC-Cloud（k8s）** | Namespace・ResourceQuota・NetworkPolicy |

アプリケーションのデプロイや LC-Cloud インフラ構築自体はこのリポジトリの対象外です。

---

## リポジトリ構成

```text
microservices-terraform/
├── terraform/
│   ├── platform/      # 🔴 管理者のみ（IdP・メンバー・クォータ・GitHub Org）
│   ├── catalog/       # 🟡 権限者が編集、誰でも PR 可（チーム・プロジェクト・請求アカウント）
│   ├── workspaces/    # 🟢 チーム・個人の自由空間（CODEOWNERS に従う）
│   └── modules/       # 🔴 管理者が管理する共通モジュール
├── documents/terraform/  # 設計ドキュメント（下記参照）
└── .github/              # Actions ワークフロー・CODEOWNERS
```

変更はすべて Pull Request 経由で行い、CODEOWNERS による承認ゲートを通過してから apply します。

---

## 設計ドキュメント

| # | ドキュメント | 内容 |
| --- | --- | --- |
| 01 | [概要](documents/terraform/01-overview.md) | 設計原則・ツール選定・管理対象一覧 |
| 02 | [リポジトリ構造](documents/terraform/02-repository-structure.md) | 3 層アクセスモデル・CODEOWNERS・State 管理 |
| 03 | [メンバー管理](documents/terraform/03-member-management.md) | 入会フロー・個人情報取り扱い・GitHub 連携 |
| 04 | [IdP 設定](documents/terraform/04-idp.md) | Authentik Terraform 設定・enrollment flow・SCIM |
| 05 | [プロジェクトライフサイクル](documents/terraform/05-project-lifecycle.md) | チーム・プロジェクト作成手順 |
| 06 | [CI/CD](documents/terraform/06-cicd.md) | GitHub Actions plan/apply・GitHub Secrets 認証 |
| 07 | [クォータ](documents/terraform/07-quota.md) | LC-Cloud クォータティア定義 |
| 08 | [請求アカウント](documents/terraform/08-billing.md) | 個人・チーム請求アカウント・予算管理 |
| 09 | [コスト定義](documents/terraform/09-costs.md) | クレジット単価・CloudKitty 設定 |
| 10 | [ロール・権限](documents/terraform/10-roles-and-permissions.md) | ロール定義・権限マトリクス・GitHub Teams |
| 11 | [ワークスペース設定](documents/terraform/11-workspace-config.md) | project-config.yaml・Tier 3 の使い方 |
| 12 | [OpenStack リソース](documents/terraform/12-openstack-resources.md) | Keystone・Nova・Neutron・Cinder 設定 |
| 13 | [運用レイヤー](documents/terraform/13-operation-layers.md) | 運用責任分離・エスカレーションフロー |
| 14 | [ミドルウェアアーキテクチャ](documents/terraform/14-middleware-architecture.md) | Authentik・Harbor 統合設計 |
| 15 | [ローカル開発](documents/terraform/15-local-development.md) | ローカル環境構築・act による CI ローカル実行 |
| 16 | [実装フェーズ](documents/terraform/16-implementation-phases.md) | フェーズ別構築順序・依存関係 |
| 17 | [本番構築ランブック](documents/terraform/17-production-runbook.md) | 本番環境ゼロからの構築手順 |

### 関連リポジトリ

| ドキュメント | 内容 |
| --- | --- |
| [lcc-external-app まとめ](documents/lcc-external-app.md) | 先行実装されている公開 API（LC-Cloud Middle API）の要約と、本リポジトリへの影響 |

---

## 環境構築

目的に合わせて手順書を参照してください。

| 目的 | 手順書 |
| --- | --- |
| **本番環境**をゼロから構築する | [17-production-runbook.md](documents/terraform/17-production-runbook.md) |
| **ローカル開発環境**を立ち上げる | [15-local-development.md](documents/terraform/15-local-development.md) |

---

## クイックスタート

### メンバーを追加する

1. `terraform/platform/members/active/<コホート>/members_secrets.yaml.enc` に
   email・student_id・role を追記して SOPS で暗号化
1. PR を作成 → circle-admin または tech-lead が承認 → apply
1. メンバーに招待リンクが発行される（7 日間有効）
1. メンバーが招待リンクから username・display_name・パスワードを設定
1. Bot が `auto-gen-members.yaml` を自動更新 → 次回 apply でアカウント確定

詳細は [03-member-management.md](documents/terraform/03-member-management.md) を参照してください。

### チームを作成する

1. `terraform/catalog/teams/_template/` をコピーして
   `terraform/catalog/teams/<チーム名>/` を作成
1. PR を作成 → circle-admin または lc-cloud-platform が承認 → apply

詳細は [05-project-lifecycle.md](documents/terraform/05-project-lifecycle.md) を参照してください。

---

### ローカルで CI を動かす（act）

GitHub Actions ワークフローを手元で実行するには
[act](https://github.com/nektos/act) を使います。

```bash
# セットアップ（初回のみ）
cp local/.secrets.example local/.secrets   # 値を入力する
cp local/.act.env.example local/.act.env

# plan ワークフローを実行
act pull_request \
  -W .github/workflows/plan.yml \
  --matrix stack:terraform/catalog/teams/_template

# modules-check を実行
act pull_request -W .github/workflows/modules-check.yml
```

詳細は [15-local-development.md](documents/terraform/15-local-development.md) を参照してください。

---

## 使用ツール

| 用途 | ツール |
| --- | --- |
| IaC | Terraform |
| シークレット管理 | SOPS（age 暗号化） |
| State バックエンド | Ceph RGW（S3 互換） |
| IdP | Authentik（`goauthentik/terraform-provider-authentik`） |
| コンテナレジストリ | Harbor |
| CI/CD | GitHub Actions |
| CI ローカル実行 | [act](https://github.com/nektos/act) |

---

## ロール

操作権限はロールによって管理されています。

| ロール | 概要 |
| --- | --- |
| `circle-admin` | 役員。全操作の最終承認者 |
| `tech-lead` | 技術最高責任者。platform 全体を管理 |
| `lc-cloud-infra` | LC-Cloud インフラ担当。クォータ・IdP を管理 |
| `lc-cloud-platform` | LC-Cloud プラットフォーム担当。GitHub Org・モジュールを管理 |
| `team-lead` | チームリーダー。自チームの catalog エントリを管理 |
| `member` | 一般メンバー。workspaces 内で CODEOWNERS に従い操作可能 |

詳細は [10-roles-and-permissions.md](documents/terraform/10-roles-and-permissions.md) を参照してください。
