# Middleware API アーキテクチャ

Middleware API は 2 つのバックエンドサービスで構成します。
ルーティング・TLS・WebSocket は K8s Ingress Controller が担うため、
独立した API Gateway サービスは不要です。

---

## デプロイ環境

両サービスとも **Kubernetes 上**で動作します（`lc-platform` Namespace）。

```text
lc-platform Namespace
  ├─ ingress-controller（External LB 付き）
  ├─ infra-api + vault-agent サイドカー
  └─ k8s-api（in-cluster ServiceAccount）
```

K8s 上で動かすことで以下が得られます。

- Vault Agent サイドカーが使える（K8s Auth Method）
- k8s-api は in-cluster ServiceAccount で Kubernetes API に直接アクセスできる
- infra-api は OpenStack API エンドポイントに HTTP で通信する

---

## 全体構成

```text
Internet
  │ HTTPS / WebSocket
  ▼
Ingress Controller（Traefik / Nginx）
  │  TLS 終端・パスルーティング・WebSocket 透過プロキシ
  ├─ /api/infra/* ──→  infra-api（OpenStack 全操作・課金・監査）
  └─ /api/k8s/*  ──→  k8s-api（Kubernetes 操作）

各サービスが JWT を自前で検証する。
```

---

## サービス一覧

| サービス | 担当 | 外部公開 |
| --- | --- | --- |
| **Ingress Controller** | TLS・ルーティング・WebSocket | ✅（External LB） |
| **infra-api** | OpenStack 全操作・課金・監査 | ✅（Ingress 経由） |
| **k8s-api** | Kubernetes 操作 | ✅（Ingress 経由） |

独立サービスとして立てないもの:

| 役割 | 代替手段 |
| --- | --- |
| API Gateway | Ingress Controller で代替 |
| credential-service | Vault Agent（Vault トークン注入）+ infra-api の動的取得 |
| auth-service | Authentik が OIDC を担当。コールバック処理は infra-api に内包 |
| audit-service | infra-api の `audit/` モジュールが担当（Loki 検索・Discord 通知） |

---

## infra-api

OpenStack の全操作・課金・監査を担当する。内部はドメインごとにモジュール分割するが、
デプロイ単位は 1 サービス。

### 内部モジュール構成

```text
infra-api/
  ├─ auth/        # OIDC コールバック・JWT 検証ミドルウェア
  ├─ compute/     # Nova VM・Cinder ボリューム
  ├─ network/     # Neutron SG・Floating IP・Designate DNS
  ├─ storage/     # Swift・Manila
  ├─ database/    # Trove
  ├─ billing/     # CloudKitty コスト・クォータ使用量・申請
  └─ audit/       # 操作ログ（Loki 書き込み・検索）・Discord 通知
```

### エンドポイント

```text
# 認証
GET    /api/infra/auth/login
GET    /api/infra/auth/callback
POST   /api/infra/auth/refresh
DELETE /api/infra/auth/logout
GET    /api/infra/auth/me

# VM（Nova）
GET    /api/infra/projects/{project}/vms
GET    /api/infra/projects/{project}/vms/{id}
POST   /api/infra/projects/{project}/vms
DELETE /api/infra/projects/{project}/vms/{id}
POST   /api/infra/projects/{project}/vms/{id}/start
POST   /api/infra/projects/{project}/vms/{id}/stop
POST   /api/infra/projects/{project}/vms/{id}/reboot
GET    /api/infra/projects/{project}/vms/{id}/console
GET    /api/infra/projects/{project}/vms/{id}/logs
POST   /api/infra/projects/{project}/vms/{id}/snapshots
GET    /api/infra/projects/{project}/vms/{id}/logs        # SSE
POST   /api/infra/projects/{project}/vms/{id}/volumes/{vol_id}
DELETE /api/infra/projects/{project}/vms/{id}/volumes/{vol_id}

# ボリューム（Cinder）
GET    /api/infra/projects/{project}/volumes
POST   /api/infra/projects/{project}/volumes
DELETE /api/infra/projects/{project}/volumes/{id}

# ネットワーク・DNS
GET    /api/infra/projects/{project}/secgroups
GET    /api/infra/projects/{project}/floatingips
POST   /api/infra/projects/{project}/floatingips/{id}/associate
DELETE /api/infra/projects/{project}/floatingips/{id}/associate
GET    /api/infra/projects/{project}/dns/records
POST   /api/infra/projects/{project}/dns/records
DELETE /api/infra/projects/{project}/dns/records/{id}

# オブジェクトストレージ（Swift）
GET    /api/infra/projects/{project}/buckets
GET    /api/infra/projects/{project}/buckets/{name}/usage
POST   /api/infra/projects/{project}/buckets/{name}/tempurl

# データベース（Trove）
GET    /api/infra/projects/{project}/databases
GET    /api/infra/projects/{project}/databases/{id}
POST   /api/infra/projects/{project}/databases/{id}/start
POST   /api/infra/projects/{project}/databases/{id}/stop
POST   /api/infra/projects/{project}/databases/{id}/backups
GET    /api/infra/projects/{project}/databases/{id}/backups
POST   /api/infra/projects/{project}/databases/{id}/databases
POST   /api/infra/projects/{project}/databases/{id}/users
DELETE /api/infra/projects/{project}/databases/{id}/users/{name}

# 課金・クォータ（billing/）
GET    /api/infra/projects/{project}/costs
GET    /api/infra/projects/{project}/costs/history
GET    /api/infra/projects/{project}/quota
POST   /api/infra/projects/{project}/quota/requests
GET    /api/infra/projects/{project}/quota/requests

# 監査ログ（audit/）
GET    /api/infra/projects/{project}/audit/logs           # SSE（?stream=true 時）
GET    /api/infra/audit/logs                              # SSE（?stream=true 時、管理者のみ）

# 共通参照
GET    /api/infra/catalog/flavors
GET    /api/infra/catalog/images
```

`GET /api/infra/projects/{project}/costs` は CloudKitty API から取得する今月のコストです。
`POST /api/infra/projects/{project}/quota/requests` はクォータ増加申請で、
`catalog/billing-accounts/` に GitHub PR を自動作成します。申請の追跡は GitHub API 経由で行います。
`GET /api/infra/audit/logs` は管理者ロールのみアクセス可能です。

---

## k8s-api

Kubernetes の運用操作を担当する。
Deployment / Service / Ingress の定義は GitOps（ArgoCD/FluxCD）が管理するため、
k8s-api は**読み取りと即時操作のみ**行う。

`{project}` パラメータは Kubernetes の Namespace 名と 1:1 対応する
（例: project `web` → namespace `web`）。

### エンドポイント

```text
# Pod
GET    /api/k8s/projects/{project}/pods
GET    /api/k8s/projects/{project}/pods/{pod}/logs        # SSE
POST   /api/k8s/projects/{project}/pods/{pod}/exec        # WebSocket

# Deployment
GET    /api/k8s/projects/{project}/deployments
POST   /api/k8s/projects/{project}/deployments/{name}/restart

# ストレージ
GET    /api/k8s/projects/{project}/pvcs
```

`pods/{pod}/logs` は SSE（サーバー → クライアントの一方向ストリーム）。
`pods/{pod}/exec` は stdin を送る必要があるため WebSocket（双方向）。
Ingress Controller が透過プロキシするため、k8s-api 側の実装は通常の HTTP で構わない。

---

## 認証フロー

```text
1. ユーザーが /api/infra/auth/login にアクセス
2. infra-api が Authentik の認証エンドポイントにリダイレクト
3. Authentik で認証完了 → /api/infra/auth/callback にリダイレクト
4. infra-api がセッショントークン（JWT）を発行
5. 以降のリクエストは Authorization: Bearer <jwt> を付与
6. 各サービスが JWT を検証（Authentik の JWKS エンドポイントを使用）
```

k8s-api も同じ JWT を受け付ける（Authentik の公開鍵で検証）。

---

## Application Credential の管理（infra-api）

Vault Agent サイドカーは **Vault トークンのみ**を注入します。
OpenStack の Application Credential は**リクエスト時にプロジェクト名をキーとして動的取得**します。
Pod 起動時に1セットのファイルを固定注入する設計では、複数プロジェクトの
Application Credential を扱えないためです。

```text
[infra-api Pod]
  ├─ infra-api コンテナ
  │     起動時:
  │       /vault/secrets/vault-token を読んで Vault クライアントを初期化
  │     リクエスト受信時:
  │       vault.Read("kv/app-creds/{project}")
  │         → app-cred-id, app-cred-secret を取得（メモリキャッシュ TTL: 5分）
  │         → OpenStack API 呼び出しに使用
  └─ vault-agent サイドカー
        K8s ServiceAccount で Vault K8s Auth
        /vault/secrets/vault-token を書き込み・自動更新
```

`catalog/projects/` の Terraform が Application Credential を作成した後、
同じ apply で Vault の `kv/app-creds/{project}` に書き込む。

```text
# Vault パス設計
kv/app-creds/web/      # app-cred-id, app-cred-secret
kv/app-creds/api/
kv/app-creds/infra/
```

---

## k8s-api の認証

k8s-api は Kubernetes 上で動作するため、in-cluster ServiceAccount で
Kubernetes API に直接アクセスします。Vault Agent サイドカーは不要です。

```text
[k8s-api Pod]
  └─ k8s-api コンテナ
        /var/run/secrets/kubernetes.io/serviceaccount/token
        → K8s API Server に直接アクセス
```

付与する ClusterRole は最小限（読み取り・exec・restart のみ）。

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]
```
