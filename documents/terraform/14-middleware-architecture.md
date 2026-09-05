# Middleware API アーキテクチャ

Middleware API は **infra-api・billing-api・k8s-api** の3サービスで構成します。
認証・ルーティング・TLS・WebSocket は既存のコンポーネント（Ingress Controller・
Authentik）に任せるため、これら以外の独立サービスは作りません。

| 役割 | 自作しない・代替する既存コンポーネント |
| --- | --- |
| API Gateway | Ingress Controller |
| 認証（ログイン・セッション管理） | Authentik Outpost（forward-auth） |
| Application Credential の受け渡し | Vault Agent サイドカー |
| 監査ログの検索・可視化 | Grafana + Loki（既存の監視スタック） |

実装言語は **Go** を使います（OpenStack は `gophercloud`、Kubernetes は
`client-go`。単一バイナリでコンテナイメージがシンプルになり、
`terraform-provider-openstack` 等このリポジトリの他のツールチェーンとも
言語が揃います）。

---

## サービス一覧

| コンポーネント | 種別 | 担当 | 永続化 | 公開パス |
| --- | --- | --- | --- | --- |
| Ingress Controller | 既存インフラ | TLS 終端・ルーティング・WebSocket 透過プロキシ・SPA 静的配信 | なし | `/` 他 |
| Authentik Outpost | 既存インフラ（Authentik本体の機能） | forward-auth。未ログインならログイン画面へ、ログイン済みならユーザー情報をヘッダーで注入 | なし（Authentik本体が保持） | `/outpost.goauthentik.io/*` |
| **infra-api** | 自作 | OpenStack 操作（compute/network/storage/database） | なし（ステートレス） | `/api/infra/*` |
| **billing-api** | 自作 | 請求アカウント（予算・コスト集計・クォータ申請） | billing-api DB（Postgres, 小） | `/api/billing/*` |
| **k8s-api** | 自作 | Kubernetes 操作（Pod/Deployment/PVC） | なし（ステートレス） | `/api/k8s/*` |

3サービスとも Kubernetes 上（`lc-platform` Namespace）で動作します。
GUI（管理ポータルの SPA）もこの Ingress の**同一ドメイン**から静的配信します
（理由は次節）。

```text
Internet
  │ HTTPS / WebSocket
  ▼
Ingress Controller（console.lc-cloud.example.internal 1ドメインにまとめる）
  │  forward-auth で Authentik Outpost に問い合わせる
  ├─ /outpost.goauthentik.io/*  ──→  Authentik Outpost（ログイン・コールバック・ログアウト）
  ├─ /api/infra/*               ──→  infra-api
  ├─ /api/billing/*             ──→  billing-api
  ├─ /api/k8s/*                 ──→  k8s-api
  └─ /（それ以外すべて）          ──→  SPA 静的ファイル配信

3サービスとも Outpost が注入した X-authentik-* ヘッダーを信頼するだけで、
互いに直接通信しない（infra-api → billing-api のような呼び出しは無い）。
```

サービス間で直接通信しない理由は単純です。billing-api が表示するコストは
CloudKitty から直接取得すればよく、infra-api の操作結果を billing-api に
逐一通知する必要もありません（コストは CloudKitty の collector が
OpenStack・Kubernetes の実使用量を見て自動算出するため）。

---

## 認証（Authentik Outpost）

ログイン・セッション管理・OIDC のやり取りはすべて Authentik の
**Proxy Provider + Outpost**（forward-auth）機能に任せます。
infra-api 等が OIDC クライアントを兼ねる自前実装は行いません。

> Proxy Provider・Outpost は Authentik の無償 Community 版に含まれる機能です
> （Enterprise 限定ではありません）。

### 仕組み

```text
Browser
  │
  ▼
Ingress Controller（nginx.ingress.kubernetes.io/auth-url アノテーション）
  │  すべてのリクエストを一旦 Outpost に問い合わせる
  ▼
Authentik Outpost
  ├─ 未ログイン → ログイン画面へリダイレクト（/outpost.goauthentik.io/start）
  └─ ログイン済み → 200 を返し、以下のヘッダーを付与
       X-authentik-username
       X-authentik-groups
       X-authentik-email
       X-authentik-name
       X-authentik-uid
  ▼
infra-api / billing-api / k8s-api / SPA 静的配信
  （ヘッダーをそのまま信頼する。Outpost を経由しない経路から
  直接到達できないよう NetworkPolicy で塞ぐ）
```

Ingress には以下のアノテーションを設定します（nginx-ingress の場合）。

```yaml
nginx.ingress.kubernetes.io/auth-url: |
  http://ak-outpost-middleware.lc-platform.svc.cluster.local:9000/outpost.goauthentik.io/auth/nginx
nginx.ingress.kubernetes.io/auth-signin: |
  https://console.lc-cloud.example.internal/outpost.goauthentik.io/start?rd=$scheme://$host$escaped_request_uri
nginx.ingress.kubernetes.io/auth-response-headers: |
  Set-Cookie,X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid
```

ログアウトは `https://console.lc-cloud.example.internal/outpost.goauthentik.io/sign_out`
にブラウザで直接アクセスするだけです（GUI のログアウトボタンから
フルページ遷移させる。次節参照）。

### Terraform（`terraform/platform/idp/provider_middleware.tf`）

```hcl
resource "authentik_provider_proxy" "middleware" {
  name               = "lc-cloud-middleware"
  mode               = "forward_single"
  external_host      = "https://console.lc-cloud.example.internal"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
}

resource "authentik_application" "middleware" {
  name              = "LC-Cloud Console"
  slug              = "lc-cloud-console"
  protocol_provider = authentik_provider_proxy.middleware.id
}

resource "authentik_outpost" "middleware" {
  name               = "lc-cloud-middleware-outpost"
  protocol_providers = [authentik_provider_proxy.middleware.id]
}
```

`mode = forward_single` を使います（GUI・3サービスとも同一ドメイン配下に
パスで同居しているため、複数ドメインをまたぐ `forward_domain` は不要です）。
Outpost 本体は `lc-platform` Namespace に `authentik/proxy` イメージの
Deployment としてデプロイし、Argo CD 管理下のアドオンとして扱います
（`13-operation-layers.md`「アドオン」層）。

---

## フロントエンド（GUI）からの利用方法

GUI 開発者が最初に知っておくべきことは一つだけです。
**トークンを一切扱いません。** ログインもトークンの保持・送信も、
すべてブラウザの Cookie と Ingress の forward-auth が代行します。
`Authorization: Bearer ...` ヘッダーを組み立てるコードは不要です。

### なぜ SPA と API を同一ドメインに置くか

GUI（SPA の静的ファイル）と `/api/*` を**同じドメイン**
（`console.lc-cloud.example.internal`）から配信します。異なるドメインに
分けると、Cookie を送るために CORS（`Access-Control-Allow-Credentials`）と
Cookie の `SameSite=None; Secure` 設定が必要になり、余計な複雑さが増えます。
同一ドメインにすることでこの問題ごと避けられます。

### 初回アクセス（何もしなくてよい）

ユーザーがブラウザで `https://console.lc-cloud.example.internal/` を開くと、
これは通常のページ遷移なので forward-auth のリダイレクトがそのまま機能します。
未ログインなら Authentik のログイン画面が表示され、ログイン完了後に
元のページへ自動的に戻ってきます。GUI 側で作り込む処理はありません。

### 実行中の API 呼び出しで注意すること（重要）

SPA が起動した**後**に `fetch()`/`XHR` で `/api/*` を呼ぶ場合、ブラウザの
セッションが有効な間は Cookie が自動送信され、透過的に成功します。

問題は**セッションが途中で切れた場合**です。forward-auth は未認証を
検知すると 302 でログイン画面へリダイレクトしますが、`fetch()` は既定で
リダイレクトを自動的に追従するため、**HTTP ステータスは 200 のまま、
中身が JSON ではなく Authentik のログイン画面の HTML になって返ってきます**。
`response.ok` だけを見るコードはこれを検知できません。

対策として、API 呼び出しは共通のラッパー関数を通し、
`Content-Type` が `application/json` でなければ「セッション切れ」とみなして
フルページ遷移でログイン画面に飛ばします。

```javascript
async function apiFetch(path, options = {}) {
  const res = await fetch(path, { ...options, credentials: "same-origin" });
  const contentType = res.headers.get("content-type") || "";

  if (!contentType.includes("application/json")) {
    // forward-auth によるログイン画面へのリダイレクトを踏んだ
    // （セッション切れ）。フルページ遷移で再ログインさせる。
    window.location.href =
      "/outpost.goauthentik.io/start?rd=" + encodeURIComponent(location.href);
    return new Promise(() => {}); // 遷移するのでここでは解決しない
  }

  if (!res.ok) {
    const body = await res.json();
    throw new ApiError(body.error.code, body.error.message);
  }
  return res.json();
}
```

各サービスは全レスポンス（エラー含む）で必ず
`Content-Type: application/json` を返す必要があります（後述「API規約」）。
これによりこの判定が確実に機能します。

### 「自分は誰か」を知る方法

3サービスとも `GET /api/{infra,billing,k8s}/me` を実装し、Outpost が
注入したヘッダーをそのまま JSON にして返します。GUI はログイン直後に
これを呼んでユーザー名・所属グループを取得し、画面表示や
「このプロジェクトは自分のチームか」の判定に使います。

```json
GET /api/infra/me
{
  "username": "alice",
  "email": "alice@example.com",
  "groups": ["team-web", "all-members"]
}
```

### WebSocket / SSE（VMコンソール・Pod exec・ログストリーム）

`WebSocket` も `EventSource`（SSE）も同一オリジンであれば Cookie を
自動送信するため、追加のトークン受け渡しは不要です。ただし forward-auth の
認証チェックは接続開始時（HTTP ハンドシェイク）の1回だけなので、
接続の途中でセッションが切れても**接続自体は張られたまま**になります
（明示的には切断されません）。長時間接続する画面（VMコンソール等）では、
接続エラー・予期しない切断を「セッション切れかもしれない」として扱い、
再接続前に `GET /api/infra/me` を呼んで生存確認する実装を推奨します。

---

## チーム・プロジェクト・Namespace の対応関係

infra-api・k8s-api・billing-api の認可とデータモデルは、既存の
`catalog/` Terraform が実際に何を作っているかにそのまま従います。
先に全体像を押さえます。

```text
catalog/teams/<team>/          ← 1チーム = 1 Keystone project + 1 Authentik group
  openstack_identity_project_v3.this.name  = var.team_name
  authentik_group.this.name                = var.team_name   （同じ名前）
  module.quota                              ← クォータはここに設定する
                                               （CloudKitty の OpenStack 側コストも
                                               この Keystone project 単位でしか測れない）

catalog/projects/<name>/       ← チームの Keystone project の中に
                                  network/subnet + Application Credential を作るだけ。
                                  自分の Keystone project は持たない
  var.team_project_id  = チームの openstack_project_id（必須入力）
  network name = var.project_name

workspaces/<name>/             ← 実際の VM・K8s リソース
  modules/kubernetes-namespace の name = var.project_name
  （catalog/projects/<name> と同じ名前。チーム名ではない）
```

つまり **1チーム(=1 Keystoneプロジェクト)の中に、複数の `catalog/projects/`
ワークスペース（＝複数の K8s Namespace）が存在しうる**、という構造です。
多くの場合はチーム1つにつきワークスペースも1つですが、スキーマ上は
1:N です。個人アカウントも同じ形で、チームの代わりに「本人1人だけの
Keystone project」を1つ持ちます（`platform/members/` 側の自動作成は
まだ未実装。`08-billing.md` 参照）。

課金の単位（請求アカウント）はこのチーム／ワークスペースの構造とは
**独立**しています。「billing-api」節で見るとおり、請求アカウントは
Keystone project・K8s Namespace を直接指定して課金対象にする権威で、
チーム・ワークスペースの所有関係から自動的に決まるものではありません。

### infra-api・k8s-api の `{project}` は何を指すか

URL の `{project}` は **`catalog/projects/<name>/` のワークスペース名**
（＝ K8s Namespace 名）を指します。Keystone project 名（チーム名）とは
別物です。1つのワークスペースの VM 操作は、そのワークスペースが属する
チームの Keystone project に対して行われます。

infra-api は「このワークスペースを操作してよいか」を判定するために
「このワークスペースはどのチームのものか」を知る必要があります。
これは Application Credential を取り出す Vault の読み取りに相乗りさせます。

```text
kv/app-creds/{project}   （project = ワークスペース名）
  app_cred_id
  app_cred_secret
  team_name        ← このワークスペースを所有するチーム名（認可判定に使う）
```

`catalog/projects/<name>/` の Terraform apply 時に、Application
Credential の発行と同じタイミングでこの `team_name` も一緒に Vault へ
書き込みます（`var.team_name` を新たに入力変数として追加する必要があります。
現状の `catalog/projects/_template/variables.tf` は `team_project_id`
のみで、`team_name` を独立して持っていないため）。

### 認可の判定方法（infra-api・k8s-api）

```text
1. Vault の kv/app-creds/{project} を読む（Application Credential 取得と共通）
2. team_name を取り出す
3. X-authentik-groups にその team_name が含まれていれば許可
```

Keystone の role assignment を都度解決する必要も、Authentik と Keystone
の間でトークン交換する必要もありません。実際の OpenStack API 呼び出しは、
認可判定とは別に、同じ Vault の読み取りで得た Application Credential で
行います（「infra-api」節「Application Credential の管理」参照）。

> 上記はワークスペース単位の「入れるか入れないか」の二値判定です。
> 将来 member/reader のようなロール粒度で制御したくなったら、
> ユーザー自身の Keystone federation スコープ済みトークンを都度取得して
> それで OpenStack を呼ぶ方式に切り替えます。

### billing-api の認可: 請求アカウントに紐づく「リンク」を見る

**請求アカウントは、どの OpenStack project・K8s Namespace の費用を
負担するかを決める権威です。** チームやプロジェクトの下にぶら下がる
ものではなく、逆に請求アカウント側が「自分はどの OpenStack project・
Namespace の費用を見るか」を直接指定します（次節「billing-api」の
データモデル参照）。

なので認可も、Vault や Keystone に問い合わせるのではなく、請求アカウント
自身が持つ「管理・閲覧のための紐づけ」（チーム名・ワークスペース名・
ユーザーID のいずれか）と `X-authentik-groups`/`X-authentik-username`
を比較するだけです。

```text
billing_account_links に以下のいずれかが存在すれば許可:
  link_type = "user" かつ link_ref == X-authentik-username
  link_type = "team" かつ link_ref が X-authentik-groups に含まれる
  link_type = "project" かつ、そのワークスペースの所有チーム
    （kv/app-creds/{link_ref}.team_name。infra-api と同じ仕組みを再利用）
    が X-authentik-groups に含まれる
```

`GET /api/billing/me/accounts`（自分がアクセスできる請求アカウント一覧）は
この判定をそのまま一覧フィルタとして使います。

---

## API規約（3サービス共通）

### レスポンス形式

成功時は素の JSON（オブジェクトまたは配列）を返します。失敗時は
必ず以下の形式で、HTTP ステータスも合わせて設定します。全レスポンスで
`Content-Type: application/json` を明示してください（GUI 側の
セッション切れ検知がこれに依存します。「フロントエンドからの利用方法」節参照）。

```json
{
  "error": {
    "code": "quota_exceeded",
    "message": "クォータの上限に達しています"
  }
}
```

| ステータス | 意味 |
| --- | --- |
| 400 | リクエストの形式が不正 |
| 401 | 未認証（通常は forward-auth が弾くため到達しないはず） |
| 403 | 認可NG（「認可」節の判定に落ちた） |
| 404 | 資源が存在しない |
| 409 | 状態競合（Idempotency-Key の衝突含む） |
| 422 | 形式は正しいが内容が受理できない（クォータ超過等） |

### 非同期操作

VM作成・DB作成のように OpenStack/Kubernetes 側で完了まで時間がかかる
操作は、**受理した時点で `202 Accepted` を返し**、レスポンスボディに
初期状態の資源（例: `status: "BUILD"`）を含めます。クライアントは
`GET .../{id}` をポーリングして完了を確認します。Webhook・コールバック
通知は v1 では実装しません。

### Idempotency-Key

資源を作成する POST（VM・ボリューム・DBインスタンス・Floating IP
アタッチ・クォータ増額申請など）は `Idempotency-Key` ヘッダー
（クライアント生成の UUID）を必須とします。

- 同じキー・同じリクエストボディで再送 → 最初のレスポンスをそのまま返す
  （再実行しない）
- 同じキーで異なるリクエストボディ → `409 Conflict`
- キーの保持期間は 24 時間（Redis。「永続化」節参照）

### ページネーション

一覧を返す GET はカーソル方式のページネーションに対応します。

```text
GET /api/infra/projects/{project}/vms?limit=50&cursor=xxx

{
  "items": [ ... ],
  "next_cursor": "yyy"  // 次ページが無ければ null
}
```

### ヘルスチェック

各サービスは `/healthz`（liveness）・`/readyz`（readiness）を実装します。
これらは kubelet がコンテナに直接叩くもので、Ingress を経由しないため
Outpost の認証対象外です（外部公開もされません）。

---

## infra-api

OpenStack の操作を担当します。内部はドメインごとにモジュール分割しますが、
デプロイ単位は1サービスです。

```text
infra-api/
  ├─ authz/       # X-authentik-* ヘッダーの読み取り・Vault kv/app-creds/{project} 経由の認可判定
  ├─ compute/     # Nova VM・Cinder ボリューム
  ├─ network/     # Neutron SG・Floating IP・Designate DNS
  ├─ storage/     # Swift・Manila
  └─ database/    # Trove
```

### エンドポイント

```text
GET    /api/infra/me

# VM（Nova）
GET    /api/infra/projects/{project}/vms
GET    /api/infra/projects/{project}/vms/{id}
POST   /api/infra/projects/{project}/vms
DELETE /api/infra/projects/{project}/vms/{id}
POST   /api/infra/projects/{project}/vms/{id}/start
POST   /api/infra/projects/{project}/vms/{id}/stop
POST   /api/infra/projects/{project}/vms/{id}/reboot
GET    /api/infra/projects/{project}/vms/{id}/console
GET    /api/infra/projects/{project}/vms/{id}/logs        # SSE
POST   /api/infra/projects/{project}/vms/{id}/snapshots
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

# 操作履歴（自プロジェクト分のみ。横断検索は Grafana から Loki を見る）
GET    /api/infra/projects/{project}/audit/logs           # SSE（?stream=true 時）

# 共通参照
GET    /api/infra/catalog/flavors
GET    /api/infra/catalog/images
```

### VM コンソール

`GET /vms/{id}/console` は Nova 標準の **VNC-over-WebSocket（noVNC）**を使います。
WebRTC は採用しません。VM のコンソールはプロジェクトネットワーク内
（Ingress の背後）にしかなく、クライアントは公開インターネット側にいるため、
ほぼ全セッションで TURN リレーが必須になり、WebRTC 本来の利点（P2P による
サーバー帯域節約）がほとんど得られません。それでいてトランスコード・
シグナリング・STUN/TURN という追加インフラの複雑さだけが乗ります。

```text
Browser (noVNC.js)
  │ wss://.../api/infra/projects/{project}/vms/{id}/console
  ▼
Ingress Controller（WebSocket 透過プロキシ）
  ▼
infra-api（GET /vms/{id}/console）
  │ Nova remote-consoles API を呼び、nova-novncproxy の
  │ 一時トークン付き websocket URL を取得して返す
  ▼
nova-novncproxy（OpenStack 既存コンポーネント。追加インフラ不要）
```

infra-api は「Nova から一時 URL を取得してクライアントに渡す」だけで、
VNC ストリーム自体は `nova-novncproxy` がそのまま流します。
低遅延なフルスクリーン共有等、noVNC では満たせない要件が具体的に出たら、
`console-bridge` Pod（VNC→WebRTC 変換）+ 共有 TURN サーバーの追加構成を
検討します（現時点では作りません）。

### Application Credential の管理

Vault Agent サイドカーは **Vault トークンのみ**を注入します。
OpenStack の Application Credential は**リクエスト時にプロジェクト名を
キーとして動的取得**します。Pod 起動時に1セットのファイルを固定注入する
設計では、複数プロジェクトの Application Credential を扱えないためです。

```text
[infra-api Pod]
  ├─ infra-api コンテナ
  │     起動時: /vault/secrets/vault-token を読んで Vault クライアントを初期化
  │     リクエスト受信時:
  │       vault.Read("kv/app-creds/{project}")
  │         → app-cred-id, app-cred-secret を取得（メモリキャッシュ TTL: 5分）
  │         → OpenStack API 呼び出しに使用
  └─ vault-agent サイドカー
        K8s ServiceAccount で Vault K8s Auth
        /vault/secrets/vault-token を書き込み・自動更新
```

`catalog/projects/` の Terraform が Application Credential を作成した後、
同じ apply で Vault の `kv/app-creds/{project}` に書き込みます。

```text
# Vault パス設計
kv/app-creds/web/      # app-cred-id, app-cred-secret（プロジェクトごと）
kv/app-creds/api/
kv/app-creds/infra/
```

水平スケール時、各 Pod は独立に Vault を叩くだけなので実害はありませんが、
Application Credential をローテーションした場合の反映は Pod ごとに
最大 TTL（5分）分ズレます。

---

## k8s-api

Kubernetes の運用操作を担当します。Deployment / Service / Ingress の定義は
GitOps（ArgoCD/FluxCD）が管理するため、k8s-api は**読み取りと即時操作のみ**
行います。

`{project}` パラメータは Kubernetes の Namespace 名と1:1対応します
（例: project `web` → namespace `web`）。

### エンドポイント

```text
GET    /api/k8s/me

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

`pods/{pod}/logs` は SSE（サーバー → クライアントの一方向ストリーム）、
`pods/{pod}/exec` は stdin を送る必要があるため WebSocket（双方向）です。
Ingress Controller が透過プロキシするため、k8s-api 側の実装は通常の
HTTP で構いません。

### 認証

k8s-api は Kubernetes 上で動作するため、in-cluster ServiceAccount で
Kubernetes API に直接アクセスします。Vault Agent サイドカーは不要です。

```text
[k8s-api Pod]
  └─ k8s-api コンテナ
        /var/run/secrets/kubernetes.io/serviceaccount/token
        → K8s API Server に直接アクセス
```

付与する ClusterRole は最小限（読み取り・exec・restart のみ）です。

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]
```

---

## billing-api

**請求アカウント**（`08-billing.md`。コード上は「Organization」と
呼ばれることもあります。`16-implementation-phases.md` [P3] 参照）の
予算・コスト集計・クォータ申請を担当します。infra-api・k8s-api から
分離しているのは、予算・Credit残高という**壊れてはいけないデータ**を、
OpenStack API 呼び出しが多く障害の影響を受けやすい infra-api と
同じ障害ドメイン・同じ権限に置きたくないためです。

### 請求アカウントは課金対象を決める権威（チーム・プロジェクトの下にはぶら下がらない）

請求アカウントは「どの OpenStack project・どの K8s Namespace の費用を
自分が負担するか」を**直接指定する側**です。「このチームの請求アカウントは
これ」という所有関係から逆算するのではなく、常に請求アカウント側の設定を
権威として見ます。この2つの情報は明確に分けて持ちます。

1. **課金対象リンク**（権威。コストの集計先・予算超過判定の対象を決める）
   - 対象は OpenStack project（Keystone project ID）または K8s Namespace 名。
     どちらも「チームのものか、プロジェクト（ワークスペース）のものか」は
     関係なく、同じ扱いです
2. **管理・閲覧リンク**（誰がこの請求アカウントを見る・扱ってよいか。
   チーム名・ワークスペース名・個人ユーザーのいずれかを指す）

この2つを分けておくことで、請求アカウントの数は自由に増減できます。
初期状態では「チームに1つ・プロジェクト（ワークスペース）に1つずつ」
という単純な1:1構成が典型ですが、後から複数チームをまとめて1つの
請求アカウントにする（統合）、逆に1チームの中の特定ワークスペースだけ
別の請求アカウントに移す（分割）といった変更も、課金対象リンクを
張り替えるだけで行えます。チーム・プロジェクトの構造自体
（`catalog/teams/`・`catalog/projects/`）を変える必要はありません。

CloudKitty は OpenStack 用・Kubernetes 用の**2インスタンス**が別々に動き
（`collector`/`scope_attribute` が1インスタンスにつき1つまでのため。
`16-implementation-phases.md`）、それぞれ Keystone project 単位・
Namespace 単位でしかコストを知りません。請求アカウントの予算判定は
「紐づけた OpenStack project の CloudKitty コスト合計 + 紐づけた
Namespace の CloudKitty コスト合計」に対して行う必要があり、これは
CloudKitty のどちらのインスタンス単体でもできないため、billing-api が
集計層として要ります。

### エンドポイント

```text
GET    /api/billing/me/accounts                          # 自分がアクセスできる請求アカウント一覧

GET    /api/billing/accounts/{id}
GET    /api/billing/accounts/{id}/costs
GET    /api/billing/accounts/{id}/costs/history
GET    /api/billing/accounts/{id}/quota
POST   /api/billing/accounts/{id}/quota/requests          # クォータ増額申請
GET    /api/billing/accounts/{id}/quota/requests

# この請求アカウントが何を課金対象にしているか・誰が管理できるか（閲覧のみ）
GET    /api/billing/accounts/{id}/resources
GET    /api/billing/accounts/{id}/links
```

`POST .../quota/requests` は `catalog/billing-accounts/` に GitHub PR を
自動作成します。申請の状態（申請中／承認済み／却下）は billing-api 側に
保存せず、`GET .../quota/requests` のたびに GitHub API へ問い合わせて
PR の状態をそのまま返します（PR がそのまま状態機械）。この PR 作成には
billing-api 用の GitHub App（リポジトリへの PR 作成権限のみ）が必要です。

課金対象リンク・管理リンクの**変更**（作成・付け替え・削除）はこの公開
API では行いません。他のチーム・プロジェクトの構造（`catalog/teams/`・
`catalog/projects/`）と同じく Terraform + PR レビューで行います
（「Terraform 連携」節）。`/api/billing/*` 側は読み取り専用です。

### データモデル

```text
billing_accounts
  id
  budget_limit_credits     -- 月次予算（Credit）
  over_budget               -- 今月100%到達済みか
  updated_at

billing_account_resources   -- 課金対象リンク（権威）。1つの resource は
                              -- 高々1つの請求アカウントにしか属さない
  billing_account_id
  resource_type              -- openstack_project | k8s_namespace
  resource_ref                -- resource_type=openstack_project: Keystone project ID
                              -- resource_type=k8s_namespace:     Namespace 名

billing_account_links       -- 管理・閲覧リンク（認可判定に使う。「誰が見るか」で
                              -- あって「何を課金するか」ではない）
  billing_account_id
  link_type                  -- team | project | user
  link_ref                    -- team_name（catalog/teams の名前）
                              -- project_name（catalog/projects のワークスペース名）
                              -- authentik user id
                              -- のいずれか

cost_cache                    -- 集計結果のキャッシュ（生データは CloudKitty 側が一次情報）
  billing_account_id
  period
  openstack_cost_credits       -- resource_type=openstack_project 分の合計
  k8s_cost_credits              -- resource_type=k8s_namespace 分の合計
  total_cost_credits
  computed_at
```

`billing_accounts`・`billing_account_resources`・`billing_account_links`
は Terraform 管理下に置きます（後述）。`cost_cache` は billing-api
自身が内部的に使うだけのテーブルで、Terraform では触りません。

典型的な初期構成（チームに1つ・そのチームのワークスペースに1つ、を
1つの請求アカウントにまとめる場合）はこうなります。

```text
billing_accounts:            { id: 1, budget_limit_credits: 15000 }
billing_account_resources:   { billing_account_id: 1, resource_type: openstack_project, resource_ref: <teamのKeystone project ID> }
                              { billing_account_id: 1, resource_type: k8s_namespace,     resource_ref: "web" }
billing_account_links:       { billing_account_id: 1, link_type: team, link_ref: "web" }
```

### コスト集計は CronJob で行う

`GET /costs` のたびに CloudKitty 2インスタンスへ都度問い合わせるのではなく、
K8s CronJob（1時間おき等）で事前に集計し `cost_cache` を更新します。
`GET /costs` はこのキャッシュを読むだけにすることで、CloudKitty 側の
障害・レイテンシが billing-api の読み取り API に波及しません。

billing_account_resources の行数（管理する OpenStack project・K8s
Namespace の数）に比例して CloudKitty への問い合わせ回数が増えると、
管理対象が増えるほど CronJob の実行時間・CloudKitty への負荷が線形に
悪化します。これを避けるため、CloudKitty へは **CloudKitty インスタンス
1つにつき1回**（つまり1周期あたり合計2回）しか問い合わせません。
CloudKitty の `/v2/summary` は `groupby` にスコープキー
（OpenStack 側は `project_id`、K8s 側は `namespace`）を指定すると、
その周期の全スコープぶんのコストを1回のレスポンスでまとめて返します。
これを `resource_ref → billing_account_id` のマップ（メモリ上に
展開した `billing_account_resources`）で突き合わせて配賦することで、
管理対象の数が増えても問い合わせ回数は増えません。

```text
CronJob（billing-aggregator）
  resource_map = billing_account_resources 全件を
                 { (resource_type, resource_ref): billing_account_id } に展開

  openstack_rows = OpenStack-CloudKitty./v2/summary(groupby=[project_id], begin=対象期間, end=対象期間)
  k8s_rows       = K8s-CloudKitty./v2/summary(groupby=[namespace],   begin=対象期間, end=対象期間)

  cost_by_account = {}  # billing_account_id -> 合計
  for row in openstack_rows + k8s_rows:
    key = (openstack_project or k8s_namespace, row.scope_id)
    account_id = resource_map[key]  # 対応が無ければ課金対象外なので無視
    cost_by_account[account_id] += row.qty * row.rate

  for account in billing_accounts:
    total = cost_by_account.get(account.id, 0)
    cost_cache に total を書き込み

    if total >= budget_limit * 0.8 and 未通知: Discord へ警告
    if total >= budget_limit and not account.over_budget:
      account.over_budget = true
    if 月初 かつ account.over_budget:
      account.over_budget = false
```

`over_budget` を立てる／下ろすのはこの CronJob だけで、OpenStack・K8s
側には何も書き込みません。実際の作成ブロックは、この値を
infra-api・k8s-api・CI が問い合わせて自分で行います（次節）。

`filters` で特定の `project_id`/`namespace` だけに絞り込む方法（同じ
クエリパラメータを繰り返し指定する）も CloudKitty はサポートしています
が、絞り込み条件そのものが対象数に比例して増えるため使いません。
`groupby` だけを指定して全スコープぶんを1回で取得し、あとはメモリ上の
突き合わせで済ませる方が、対象数が増えても劣化しない構成になります。

### 予算超過の強制は billing-api への問い合わせで行う

OpenStack・Kubernetes のクォータ値そのものは Terraform（`modules/lc-cloud-quota`・
`modules/kubernetes-namespace`）が唯一の書き手であり続けます。billing-api は
これらのクォータ API を一切書き換えません（クランプという概念自体を
やめます）。理由は、billing-api が SDK 経由でクォータを直接書き換えると
Terraform の宣言値と実際の値がズレ、無関係な PR のマージで意図せず
元に戻ってしまう問題があったためです。

代わりに、予算超過の判定を持っているのは billing-api だけという前提で、
**実際にリソースを作る側（infra-api・k8s-api、および Terraform の
`workspaces/` 経路）が、作成前に billing-api へ問い合わせます。**

- **infra-api・k8s-api**: VM・ボリューム・DB・K8s リソースなど、
  課金対象を増やす操作の直前に
  `GET /internal/billing/status?resource_type=...&resource_ref=...`
  を呼び、対象の請求アカウントが `over_budget` なら Nova/Neutron/Trove/K8s
  に転送せず、その場で `budget_exceeded` エラーを返します
- **Terraform（`terraform/workspaces/**`・`catalog/projects/**`・
  `catalog/teams/**`）**: infra-api・k8s-api を経由せず直接 OpenStack/K8s
  リソースを作るこの経路にも同じ抜け道があるため、CI（`plan.yml`・
  `apply.yml`）が同じ問い合わせを行います（次節）

`/internal/billing/status` は Ingress では公開せず、`lc-platform`
Namespace 内からのみ到達可能にします。呼び出し頻度が高いため
infra-api・k8s-api 側で短時間（数十秒程度）キャッシュし、billing-api が
一時的に落ちていても**作成を許可する側にフェイルオープン**します
（予算判定より本来のインフラ操作の可用性を優先するため。誤って
超過を見逃すケースは次回の CronJob 実行で検知され、以降の作成分から
ブロックされます）。

既存リソースは引き続き影響を受けません。ブロックされるのは
新規作成リクエストだけです。

> **将来の拡張**: 上記は「新規作成のブロック」までで、既存リソースの
> 強制停止は行いません。使用者への直接アラート（現状は運用者向け
> Discord チャンネルへの通知のみ）と、予算超過が続いた場合の既存
> リソースの強制停止（Nova インスタンスの stop、対象 Namespace の
> Deployment/StatefulSet を 0 レプリカにする、等）は、別の拡張として
> 段階的に追加します。通知先の解決（`link_type=user` なら Authentik
> API で email を引く、`link_type=team` ならチームごとの通知先を
> 別途持つ、等）と、強制停止の発動条件・対象範囲は今後の設計課題です。

### Terraform 連携

`08-billing.md`/`09-costs.md` が仕様として書いていた `lc_cloud_organization`・
`lc_cloud_budget` は、`modules/cloudkitty-service` と同じ手法
（`Mastercard/terraform-provider-restapi` で billing-api 自身の管理用
API を叩く）で実装します。「チーム・プロジェクトの下に請求アカウントが
ぶら下がる」のではなく、逆に**請求アカウント側が対象を指定する**形に
そのまま対応します。

```hcl
# terraform/modules/lc-cloud-organization/main.tf
resource "restapi_object" "billing_account" {
  path         = "/admin/billing-accounts"
  id_attribute = "id"
  data = jsonencode({
    budget_limit_credits = var.budget_limit_credits
  })
}

# 課金対象リンク（権威）。openstack_project と k8s_namespace を区別なく渡す
resource "restapi_object" "resource_link" {
  for_each     = var.resources  # { "openstack_project:<keystone project id>" = {...}, "k8s_namespace:web" = {...} }
  path         = "/admin/billing-account-resources"
  id_attribute = "id"
  data = jsonencode({
    billing_account_id = restapi_object.billing_account.id
    resource_type       = each.value.type
    resource_ref          = each.value.ref
  })
}

# 管理・閲覧リンク（チーム／プロジェクト／ユーザーを区別なく渡す）
resource "restapi_object" "account_link" {
  for_each     = var.links  # { "team:web" = {...}, "project:web-frontend" = {...} }
  path         = "/admin/billing-account-links"
  id_attribute = "id"
  data = jsonencode({
    billing_account_id = restapi_object.billing_account.id
    link_type            = each.value.type
    link_ref               = each.value.ref
  })
}
```

`catalog/billing-accounts/` の `data "lc_cloud_organization"` /
`resource "lc_cloud_budget"` は、この `modules/lc-cloud-organization`
経由の呼び出しに差し替えます。呼び出し元（`catalog/billing-accounts/teams/<name>/`
等）は「どの OpenStack project・Namespace を課金対象にするか」
（`var.resources`）と「どのチーム・プロジェクト・ユーザーに見せるか」
（`var.links`）を明示的に渡します。billing-api 側が「チーム配下の
ワークスペースを自動的に発見する」仕組みは持たず、対象は常に
明示的な入力で決まります。

billing-api の管理用エンドポイント（`/admin/billing-accounts` 等）は
Ingress では外部公開せず、`lc-platform` Namespace 内から Terraform CI
ランナーのみが到達できる NetworkPolicy にします（Vault の Application
Credential と同格の扱い）。

### CI（plan/apply）でも同じ問い合わせを行う

`terraform/workspaces/**`（VM・DB・K8s リソースを直接作る）・
`catalog/projects/**`・`catalog/teams/**`（ネットワーク・Application
Credential・Keystone project 等を作る）は infra-api・k8s-api を経由せず
直接 OpenStack/K8s にリソースを作る経路です。ここは実行時チェックの
対象にできないため、CI が代わりに billing-api へ問い合わせます。

- billing-api に `GET /admin/billing-accounts?link_type=team&link_ref=<name>`
  （`project`/`user` も同様）を追加し、そのチーム・プロジェクトに紐づく
  請求アカウントの `over_budget` を返せるようにする
- `plan.yml`（PR 時）・`apply.yml`（main へのマージ時）の両方に、
  変更されたディレクトリからチーム名・プロジェクト名を求めて
  このエンドポイントに問い合わせるステップを追加し、
  `over_budget = true` の請求アカウントが1つでもあれば
  そのジョブを失敗させる
- `catalog/billing-accounts/**` 自体はこのチェックの対象に含めません。
  予算を上げる・課金対象リンクを外すという、超過状態を解消するための
  変更まで塞いでしまうと詰むためです

plan の段階でブロックされるので、PR を作った時点で「予算超過中なので
今はこの変更を通せない」と分かります。apply 時にも同じチェックを
入れているのは、PR 承認から マージまでの間に新たに予算超過になる
ケースを取りこぼさないためです。

### 前提として `catalog/projects/_template` に必要な追加

「チーム・プロジェクト・Namespace の対応関係」節で触れたとおり、
infra-api・k8s-api の認可判定は `kv/app-creds/{workspace}` に書き込まれた
`team_name` を読みます。現状の `catalog/projects/_template/variables.tf`
は `team_project_id` のみで `team_name` を単独では持っていないため、
billing-api・infra-api・k8s-api の実装に先立って、以下を
`catalog/projects/_template` に追加する必要があります。

- 入力変数 `team_name`（`team_project_id` とは別に追加）
- apply 時に Vault へ `kv/app-creds/{project_name}` を書き込む処理
  （`app_cred_id`・`app_cred_secret`・`team_name` の3点）

これは `16-implementation-phases.md` Phase 6（Middleware API）着手前に
済ませておく `catalog/` 側の前提整備です。

### 必要な権限・認証情報

| 対象 | 権限 | 用途 | 取得元 |
| --- | --- | --- | --- |
| CloudKitty（OpenStack用） | 読み取りのみ | コスト集計 | Vault `kv/cloudkitty/openstack` |
| CloudKitty（K8s用） | 読み取りのみ | コスト集計 | Vault `kv/cloudkitty/k8s` |
| GitHub | 対象リポジトリへの PR 作成のみ | クォータ増額申請 | GitHub App |

billing-api は OpenStack・Kubernetes への書き込み権限を一切持ちません
（`/internal/billing/status`・`/admin/billing-accounts` はどちらも
billing-api 自身の DB を読むだけの API です）。infra-api の
Application Credential（VM作成等の実操作権限）とは完全に分離されて
おり、billing-api が仮に侵害された場合の最悪ケースは「予算超過判定を
誤魔化されて新規作成のブロックをすり抜けられる」までで、VM・ボリューム
等のリソースを直接作成・削除したり、既存のクォータ設定を書き換えたり
することはできません。

---

## 監査ログ

監査ログの書き込みは各サービスが共通の小さなロギングライブラリ経由で
直接 Loki に push します（専用サービスは作りません）。

- **プロジェクト単位の自サービス操作履歴**（例:「自分のVM操作履歴」）は
  `GET /api/infra/projects/{project}/audit/logs` に残します
  （infra-api 自身が書いた分だけを Loki から引く、範囲の狭い読み取り）
- **管理者による横断検索**は専用 API を作らず、Grafana
  （`lc-cloud-k8s-architecture.pdf` の監視スタックと共用。Authentik OIDC
  連携済み想定）から Loki を直接検索する運用にします

---

## 永続化（DB）のまとめ

| 用途 | 持つ場所 |
| --- | --- |
| 請求アカウント本体・課金対象リンク・管理リンク・コストキャッシュ（`billing_accounts`・`billing_account_resources`・`billing_account_links`・`cost_cache`） | billing-api DB（CloudNativePG、`lc-platform` Namespace に小さく1台。Authentik と同じ方式） |
| Idempotency-Key の短期記録 | billing-api・infra-api 共用の Redis（24時間 TTL） |
| セッション | 持たない（Authentik 本体が保持） |
| 監査ログ本体・メトリクス | 持たない（Loki／クラスタ内保管） |
| Terraform state | 持たない（既存方針どおりオブジェクトストレージ） |
| Application Credential・CloudKitty認証情報 | 持たない（Vault のまま） |
| クォータ増加申請の状態 | 持たない（GitHub PR がそのまま状態機械。`GET .../quota/requests` は GitHub API を都度叩く） |
| CloudKitty の使用量生データ | 持たない（billing-api は集計結果のキャッシュだけ持つ） |

---

## ローカル開発

認証を Outpost に完全委譲しているため、`infra-api`・`billing-api`・
`k8s-api` 単体の動作確認に Authentik を起動する必要はありません。
各サービスは HTTP ヘッダーを読むだけなので、開発時は `curl` や Postman で
`X-authentik-username`・`X-authentik-groups` を直接付けてリクエストすれば
足ります。

```bash
curl -H "X-authentik-username: alice" \
     -H "X-authentik-groups: team-web" \
     http://localhost:8080/api/infra/projects/web/vms
```

OpenStack・Kubernetes の実体との結合確認には `local/gcp-devstack/`・
kind クラスターを使います（`15-local-development.md`）。forward-auth・
ログイン画面を含めたエンドツーエンドの確認だけ、`local/authentik/` の
Authentik と実際に Outpost を立てて行います。
