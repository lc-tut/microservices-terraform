# 操作レイヤー設計

インフラ操作をどのレイヤーで行うかを、リソース・操作単位で定義します。

---

## レイヤー定義

| 記号 | レイヤー | 特徴 |
| --- | --- | --- |
| ✅ | **Terraform (CI/CD)** | インフラ定義・変更履歴・レビュー必須 |
| 🌐 | **Middleware API** | リアルタイム・既存リソースへの操作・参照 |
| 🔄 | **GitOps (ArgoCD/FluxCD)** | K8s アプリライフサイクル |
| 🖥 | **CLI ツール** | 認証・証明書発行・ポートフォワード |
| ❌ | **不要/禁止** | ユーザーは使わない |

---

## Terraform 管理と非管理の考え方

**Terraform で管理しなくても構わない**。クォータ・課金・Access Rules は
OpenStack が強制するため、VM がどう作られたかに関係なく適用される。

| | Terraform 管理 VM | Middleware API 作成 VM |
| --- | --- | --- |
| 用途 | 本番・長期稼働・再現が必要なもの | 実験・開発・一時的な検証 |
| 変更履歴 | PR・git log に残る | 残らない |
| 再現性 | コードから再構築可能 | 手順を覚えていないと再現不可 |
| クォータ | 消費する | 消費する |
| 課金 | CloudKitty が計上 | CloudKitty が計上 |
| レビュー | CODEOWNERS 承認が必要 | 即時作成可能 |

どちらも平等にクォータと課金の制約を受けるため、
プラットフォーム側の強制という意味では差がない。

---

## 判断基準

**Terraform を使う:**

- 長期稼働・本番相当のリソース
- 変更にレビューが必要（ファイアウォールルール・スペック変更等）
- リソース間の依存関係を追跡したい
- コードとして再現・共有したい

**Middleware API を使う:**

- 既存リソースへの操作（起動・停止・再起動）
- ステータス・ログ取得（Terraform は状態を読まない）
- リアルタイムのフィードバックが必要な操作
- 一時的・アドホックな操作（実験 VM・Temp URL 生成・バックアップ）

**GitOps を使う:**

- K8s アプリのデプロイ・ロールバック
- インフラではなくアプリのライフサイクル管理

---

## Nova（Compute）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| VM 作成（長期・本番） | ✅ | | レビュー・変更履歴が必要 |
| VM 作成（実験・一時） | | 🌐 | 即時作成。Terraform 管理不要 |
| VM 削除（Terraform 管理） | ✅ | | |
| VM 削除（非管理） | | 🌐 | API で作ったものは API で消す |
| フレーバー変更（リサイズ） | ✅ | | スペック変更はレビュー推奨 |
| VM 起動 | | 🌐 | 既存 VM への操作 |
| VM 停止 | | 🌐 | 既存 VM への操作 |
| VM 再起動 | | 🌐 | 既存 VM への操作 |
| ステータス取得 | | 🌐 | リアルタイム参照 |
| コンソール（noVNC） | | 🌐 | セッション URL を発行 |
| コンソールログ取得 | | 🌐 | リアルタイム |
| スナップショット作成（手動） | | 🌐 | アドホックバックアップ |
| スナップショットから復元 | ✅ | | インフラ再構築に相当 |
| SSH 鍵管理 | ❌ | | 🖥 CLI が SSH 証明書で代替 |
| Server Group | ✅ | | 配置ポリシー定義 |

---

## Cinder（Block Storage）

非管理 VM に紐づくボリュームは Middleware で作成して構わない。

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| ボリューム作成（Terraform 管理 VM） | ✅ | | VM と同一スタックで管理 |
| ボリューム作成（非管理 VM） | | 🌐 | VM と一緒に API で作成 |
| ボリューム削除 | ✅ | 🌐 | 作った手段に合わせる |
| サイズ拡張 | ✅ | 🌐 | |
| VM へのアタッチ | ✅ | 🌐 | 作った手段に合わせる |
| VM からのデタッチ | ✅ | 🌐 | |
| スナップショット作成（定期） | ✅ | | スケジュールは Terraform で定義 |
| スナップショット作成（手動） | | 🌐 | アドホック |
| スナップショットから復元 | ✅ | | |
| ボリューム一覧・詳細取得 | | 🌐 | 参照 |

---

## Neutron（Networking）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| ネットワーク・サブネット作成 | ✅（catalog） | | admin 管理 |
| Security Group 作成 | ✅ | | レビュー対象 |
| Security Group 削除 | ✅ | | |
| SG ルール追加 | ✅ | | ファイアウォール変更。レビュー推奨 |
| SG ルール削除 | ✅ | | |
| Floating IP 取得 | ✅ | | 課金発生。Terraform で追跡 |
| Floating IP VM への紐づけ | ✅ | | |
| Floating IP 解放 | ✅ | | 課金停止。Terraform で追跡 |
| ネットワーク一覧取得 | | 🌐 | 参照 |

> **SG ルール変更について**: 即時反映が必要な緊急時（インシデント対応）は
> Middleware からの直接変更も許容する。ただし事後に Terraform へ反映する。

---

## Swift（Object Storage）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| コンテナ作成 | ✅ | | バケット定義 |
| コンテナ削除 | ✅ | | 破壊的 |
| コンテナ設定（CORS・lifecycle）| ✅ | | |
| オブジェクトのアップロード | ❌ | | 🖥 Swift CLI / S3 CLI で直接 |
| オブジェクトのダウンロード | ❌ | | 🖥 Swift CLI / S3 CLI で直接 |
| オブジェクト削除 | ❌ | | 🖥 Swift CLI / S3 CLI で直接 |
| Temp URL 生成 | | 🌐 | アドホック・有効期限付き |
| コンテナ一覧・使用量取得 | | 🌐 | 参照 |

> **オブジェクト操作は Terraform に向いていない**: 変更のたびに apply が必要で
> state が肥大化する。S3 互換 CLI を直接使う。

---

## Glance（Image）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| ベースイメージ管理 | ✅（platform） | | admin のみ |
| カスタムイメージアップロード | ❌ | | Packer + Harbor 経由を推奨 |
| イメージ一覧・詳細取得 | | 🌐 | 参照（GUI でフレーバー選択に使用） |
| カスタムイメージ削除 | ✅ | | |

---

## Designate（DNS）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| DNS ゾーン作成 | ✅（catalog） | | admin 管理 |
| A レコード追加 | ✅ | | インフラと紐づく変更 |
| CNAME レコード追加 | ✅ | | |
| レコード削除 | ✅ | | |
| レコード一覧取得 | | 🌐 | 参照 |

---

## Barbican（Key Management）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| Secret 作成 | ✅ | | SOPS 経由で暗号化 |
| Secret 削除 | ✅ | | |
| Secret 値の取得 | | 🌐 | アプリが参照する際に使用 |
| Secret ローテーション | | 🌐 | アドホック操作 |

---

## Trove（Database）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| DB インスタンス作成 | ✅ | | インフラ定義 |
| DB インスタンス削除 | ✅ | | 破壊的。レビュー必須 |
| フレーバー変更 | ✅ | | スペック変更 |
| データベース作成 | ✅ | 🌐 | 初期定義は Terraform。運用中追加は API も可 |
| ユーザー作成 | ✅ | 🌐 | 同上 |
| ユーザー削除 | ✅ | 🌐 | |
| インスタンス停止・起動 | | 🌐 | 既存リソースへの操作 |
| ステータス取得 | | 🌐 | 参照 |
| バックアップ作成（手動） | | 🌐 | アドホック |
| バックアップから復元 | ✅ | | インフラ再構築 |

---

## Manila（Shared File System）

| 操作 | Terraform | Middleware | 備考 |
| --- | --- | --- | --- |
| Share 作成 | ✅ | | |
| Share 削除 | ✅ | | 破壊的 |
| サイズ拡張 | ✅ | | インフラ変更 |
| アクセスルール追加 | ✅ | | |
| アクセスルール削除 | ✅ | | |
| スナップショット作成（手動） | | 🌐 | アドホック |
| Share 詳細・マウントパス取得 | | 🌐 | 参照 |

---

## Kubernetes

K8s の操作は **インフラ（Terraform）・アプリ（GitOps）・運用（Middleware）** の
3 つに明確に分離します。

| 操作 | Terraform | GitOps | Middleware | 備考 |
| --- | --- | --- | --- | --- |
| Namespace 作成 | ✅（catalog） | | | admin 管理 |
| PVC 作成 | ✅ | | | ストレージ定義 |
| PVC 削除 | ✅ | | | 破壊的 |
| ConfigMap | ✅ | | | 設定のインフラ定義 |
| Secret（暗号化）| ✅（SOPS） | | | SOPS で暗号化して管理 |
| ServiceAccount | ✅ | | | 権限定義 |
| Deployment 作成・更新 | | 🔄 | | アプリのライフサイクル |
| Service | | 🔄 | | ネットワーク公開 |
| Ingress | | 🔄 | | ルーティング定義 |
| HPA | | 🔄 | | スケーリングポリシー |
| Pod 一覧取得 | | | 🌐 | 参照 |
| Pod ログ取得 | | | 🌐 | リアルタイム |
| Pod への exec | | | 🌐 | デバッグ用 |
| Deployment の rollout restart | | | 🌐 | 即時操作 |
| レプリカ数変更 | | 🔄 | 🌐 | GitOps 優先。緊急時は API も可 |

---

## Middleware API エンドポイント設計（概要）

認証は Authentik OIDC トークンで行い、プロジェクトスコープを確認してから
OpenStack / Kubernetes API を呼び出す。エンドポイントの詳細は
`14-middleware-architecture.md` を参照。

```text
# infra-api（/api/infra/...）
GET    /api/infra/projects/{project}/vms
POST   /api/infra/projects/{project}/vms
GET    /api/infra/projects/{project}/vms/{id}
DELETE /api/infra/projects/{project}/vms/{id}
POST   /api/infra/projects/{project}/vms/{id}/start
POST   /api/infra/projects/{project}/vms/{id}/stop
POST   /api/infra/projects/{project}/vms/{id}/reboot
GET    /api/infra/projects/{project}/vms/{id}/console
GET    /api/infra/projects/{project}/vms/{id}/logs        # SSE
POST   /api/infra/projects/{project}/vms/{id}/snapshots
POST   /api/infra/projects/{project}/vms/{id}/volumes/{vol_id}
DELETE /api/infra/projects/{project}/vms/{id}/volumes/{vol_id}

GET    /api/infra/projects/{project}/volumes
POST   /api/infra/projects/{project}/volumes
DELETE /api/infra/projects/{project}/volumes/{id}

GET    /api/infra/projects/{project}/secgroups
GET    /api/infra/projects/{project}/floatingips
POST   /api/infra/projects/{project}/floatingips/{id}/associate
DELETE /api/infra/projects/{project}/floatingips/{id}/associate
GET    /api/infra/projects/{project}/dns/records
POST   /api/infra/projects/{project}/dns/records
DELETE /api/infra/projects/{project}/dns/records/{id}

GET    /api/infra/projects/{project}/buckets
GET    /api/infra/projects/{project}/buckets/{name}/usage
POST   /api/infra/projects/{project}/buckets/{name}/tempurl

GET    /api/infra/projects/{project}/databases
GET    /api/infra/projects/{project}/databases/{id}
POST   /api/infra/projects/{project}/databases/{id}/start
POST   /api/infra/projects/{project}/databases/{id}/stop
POST   /api/infra/projects/{project}/databases/{id}/backups
GET    /api/infra/projects/{project}/databases/{id}/backups

GET    /api/infra/projects/{project}/costs
GET    /api/infra/projects/{project}/costs/history
GET    /api/infra/projects/{project}/quota
POST   /api/infra/projects/{project}/quota/requests
GET    /api/infra/projects/{project}/quota/requests

GET    /api/infra/projects/{project}/audit/logs           # SSE（?stream=true 時）
GET    /api/infra/audit/logs                              # SSE（?stream=true 時、管理者のみ）

GET    /api/infra/catalog/flavors
GET    /api/infra/catalog/images

# k8s-api（/api/k8s/...）
GET    /api/k8s/projects/{project}/pods
GET    /api/k8s/projects/{project}/pods/{pod}/logs        # SSE
POST   /api/k8s/projects/{project}/pods/{pod}/exec        # WebSocket
GET    /api/k8s/projects/{project}/deployments
POST   /api/k8s/projects/{project}/deployments/{name}/restart
GET    /api/k8s/projects/{project}/pvcs
```

---

## アーキテクチャ全体像

```text
ユーザー
  │
  ├─ [インフラ変更] Terraform（PR → CI → apply）
  │       │
  │       └─ OpenStack API / Kubernetes API
  │
  ├─ [運用操作・参照] Web GUI / CLI
  │       │
  │       ▼
  │   Middleware API（Authentik OIDC で認証）
  │       │  per-project Application Credential を Vault から取得
  │       ├─ OpenStack API（Nova / Cinder / Swift 等）
  │       └─ Kubernetes API（Pod / Deployment 等）
  │
  └─ [アプリデプロイ] Git push
          │
          ▼
      ArgoCD / FluxCD
          │
          └─ Kubernetes API（Deployment / Service / Ingress 等）
```

---

## まとめ：操作の性質による分類

| 性質 | レイヤー | 例 |
| --- | --- | --- |
| 長期・本番リソースの作成・削除 | Terraform | 本番 VM・ボリューム・SG |
| 実験・一時リソースの作成・削除 | Middleware | 検証用 VM・付随ボリューム |
| スペック・設定変更 | Terraform | フレーバー変更・SG ルール追加 |
| 既存リソースへの操作 | Middleware | 起動・停止・再起動 |
| 参照・監視 | Middleware | ステータス・ログ・使用量 |
| アドホック操作 | Middleware | 手動バックアップ・Temp URL |
| アプリライフサイクル | GitOps | Deployment・Ingress |
| オブジェクト転送 | CLI 直接 | ファイルアップロード・ダウンロード |
| SSH 接続・証明書 | CLI ツール | SSH 鍵発行・ポートフォワード |
