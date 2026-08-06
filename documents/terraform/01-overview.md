# Terraform リポジトリ設計概要

## 目的

本リポジトリは LinuxClub が運営する LC-Cloud のサークル運営基盤を Terraform で管理するためのものです。
以下のリソースを IaC によって一元管理します。

- サークルメンバーのアカウント（Authentik IdP）
- チーム・グループ定義（Authentik / Harbor）
- LC-Cloud リソース割り当て（ネットワーク・クォータ・予算）
- プロジェクトごとのレジストリ・OpenStack 環境・デプロイ基盤

---

## ツール選定

| 用途 | 選定 | 理由 |
| --- | --- | --- |
| IaC ツール | **Terraform** | 実績・エコシステム・プロバイダの豊富さ |
| リポジトリホスティング | **GitHub** | Actions・CODEOWNERS・Branch Protection が揃っている |
| 複雑化対策 | **Terragrunt** | DRY 化・スタック間の依存管理（規模拡大時に導入） |
| シークレット管理 | **SOPS（age 暗号化）** | PII を Git で安全に管理する |
| State バックエンド | **Ceph RGW（S3 互換）** | LC-Cloud 上に既存、暗号化済み |
| State 暗号化 | **不要** | PII を State に含めない設計 + Ceph が暗号化済み |

---

## 設計原則

### 1. インフラ定義は Terraform・運用操作は Middleware API

リソースの**作成・削除・設定変更**は Terraform で行い Git で追跡する。
VM の起動・停止・ログ取得など既存リソースへの**運用操作**は Middleware API が担当する。

実験・開発目的の一時的な VM は Middleware API から直接作成してよい。
クォータ・課金・Access Rules は Terraform 経由かどうかに関係なく OpenStack が強制する。

詳細は `13-operation-layers.md` を参照。

### 2. 最小権限の原則

3 層のアクセスモデルにより、各操作者が必要な範囲のみ変更できる設計とする
（詳細は `02-repository-structure.md` 参照）。

Workspace の CI/CD は `catalog/projects/` が発行した Access Rules 付きの
Application Credential を使用し、OpenStack API レベルで操作範囲を制限する。

### 3. PII の保護

Student Email・Student ID などの個人情報は SOPS で暗号化し、
Terraform の State には含めない設計とする（詳細は `03-member-management.md` 参照）。

### 4. チームへの権限委譲

Terraform はプロジェクトの初期セットアップ（ネットワーク・Application Credential 発行等）を担う。
セットアップ後のインフラ操作・アプリケーションデプロイはチーム・プロジェクトオーナーに委任する
（詳細は `05-project-lifecycle.md` 参照）。

### 5. PR ベースの変更管理

インフラ定義（Terraform）の変更はすべて Pull Request 経由で行い、
CODEOWNERS による承認ゲートを通過してから apply する。

---

## 管理対象リソース一覧

| サービス | 管理内容 |
| --- | --- |
| **Authentik** | ユーザ・グループ・Enrollment フロー・SSO プロバイダ定義 |
| **GitHub** | Organization・Teams・Branch Protection・CODEOWNERS |
| **Harbor** | プロジェクト・RBAC・脆弱性スキャンポリシー |
| **LC-Cloud（OpenStack）** | プロジェクト・ネットワーク・クォータ・Application Credential・Floating IP 等 |
| **LC-Cloud（Kubernetes）** | Namespace・PVC・Secret・ConfigMap・ServiceAccount |
| **Vault** | Terraform CI/CD 用シークレット・per-project Application Credential |

---

## 管理対象外

| 項目 | 理由・代替 |
| --- | --- |
| VM の起動・停止・ログ等の運用操作 | Middleware API が担当（`13-operation-layers.md`） |
| アプリケーションのデプロイ | GitOps（ArgoCD/FluxCD）がチーム・プロジェクトに委任 |
| オブジェクトストレージへのファイル転送 | Swift / S3 互換 CLI で直接操作 |
| LC-Cloud インフラ自体（OpenStack・K8s 構築） | Polaris チームの IaC リポジトリで管理 |

---

## ドキュメント一覧

| ファイル | 内容 |
| --- | --- |
| `01-overview.md` | 本ドキュメント |
| `02-repository-structure.md` | フォルダ構成・3 層アクセスモデル・CI/CD フロー |
| `03-member-management.md` | メンバー管理・PII 保護・入会フロー |
| `04-idp.md` | Authentik 設定 |
| `05-project-lifecycle.md` | チーム・プロジェクトのライフサイクル |
| `06-cicd.md` | GitHub Actions ワークフロー詳細 |
| `07-quota.md` | OpenStack クォータ設計 |
| `08-billing.md` | 請求アカウント管理 |
| `09-costs.md` | コスト・予算設計 |
| `10-roles-and-permissions.md` | ロール・権限・CODEOWNERS |
| `11-workspace-config.md` | ワークスペース設定（project-config.yaml） |
| `12-openstack-resources.md` | OpenStack リソース管理方針・Tier 分類・Access Rules |
| `13-operation-layers.md` | Terraform / Middleware / GitOps の操作レイヤー設計 |
| `14-middleware-architecture.md` | Middleware API マイクロサービスアーキテクチャ |
