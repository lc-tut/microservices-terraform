# Terraform リポジトリ設計概要

## 目的

本リポジトリは LinuxClub が運営する LC-Cloud のサークル運営基盤を Terraform で管理するためのものです。
以下のリソースを IaC によって一元管理します。

- サークルメンバーのアカウント（Authentik IdP）
- チーム・グループ定義（Authentik / Harbor）
- LC-Cloud リソース割り当て（Namespace・クォータ・予算）
- プロジェクトごとのレジストリ・デプロイ基盤

---

## ツール選定

| 用途 | 選定 | 理由 |
|------|------|------|
| IaC ツール | **Terraform** | 実績・エコシステム・プロバイダの豊富さ |
| リポジトリホスティング | **GitHub** | Actions・CODEOWNERS・Branch Protection が揃っている |
| 複雑化対策 | **Terragrunt** | DRY 化・スタック間の依存管理（規模拡大時に導入） |
| シークレット管理 | **SOPS（age 暗号化）** | PII を Git で安全に管理する |
| State バックエンド | **Ceph RGW（S3 互換）** | LC-Cloud 上に既存、暗号化済み |
| State 暗号化 | **不要** | PII を State に含めない設計 + Ceph が暗号化済み |

---

## 設計原則

### 1. Infrastructure as Code First

全リソース操作は Terraform 経由で行う。GUI や CLI での手動操作は禁止し、変更はすべて Git で追跡する。

### 2. 最小権限の原則

3 層のアクセスモデルにより、各操作者が必要な範囲のみ変更できる設計とする（詳細は `02-repository-structure.md` 参照）。

### 3. PII の保護

Student Email・Student ID などの個人情報は SOPS で暗号化し、Terraform の State には含めない設計とする（詳細は `03-member-management.md` 参照）。

### 4. チームへの権限委譲

Terraform はプロジェクトの初期セットアップ（箱づくり）のみを担う。セットアップ後のアプリケーションデプロイはチーム・プロジェクトオーナーに完全に委任する（詳細は `05-project-lifecycle.md` 参照）。

### 5. PR ベースの変更管理

すべての変更は Pull Request 経由で行い、CODEOWNERS による承認ゲートを通過してから apply する。

---

## 管理対象リソース一覧

| サービス | 管理内容 |
|----------|---------|
| **Authentik** | ユーザ・グループ・Enrollment フロー・SSO プロバイダ定義 |
| **GitHub** | Organization・Teams・Branch Protection・CODEOWNERS |
| **Harbor** | プロジェクト・RBAC・脆弱性スキャンポリシー |
| **LC-Cloud（OpenStack）** | Organization・クォータ（CPU/Memory/Pod 数） |
| **LC-Cloud（k8s）** | Namespace・ResourceQuota・NetworkPolicy・CD ツール連携（TBD） |

---

## 管理対象外

| 項目 | 理由 |
|------|------|
| アプリケーションのデプロイ | チーム・プロジェクトオーナーに委任 |
| LC-Cloud クレジット消費の追跡・制御 | LC-Cloud の `internal/billing` の責務 |
| LC-Cloud インフラ自体（OpenStack・k8s 構築） | Polaris チームの IaC リポジトリで管理 |
