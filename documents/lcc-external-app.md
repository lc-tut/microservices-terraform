# lcc-external-app（LC-Cloud Middle API）まとめ

先行して作られている公開 API 実装リポジトリ `lcc-external-app` の内容を、
`microservices-terraform` 側から読むための要約です。原典は
`apps/lcc-external-app/`（GitHub: `lc-tut/lcc-external-app`）で、本書はその写しです。
**何を正とするか・迷ったときにどうするかは [0. この文書の扱い](#0-この文書の扱い最初に読む) を先に読んでください。**

このリポジトリは `documents/terraform/14-middleware-architecture.md` が設計している
「Middleware API」に相当する層の**実装**です。ただし後述のとおり、サービス分割・認証方式・
テナントモデルの3点で 14 の設計とは異なる結論を出しています。

---

## 0. この文書の扱い（最初に読む）

### 設計・運用方針は `microservices-terraform` を優先する

**このワークスペースで作業するときの正は、原則として
`/home/hekuta/works/lc-cloud-workspace/apps/microservices-terraform` です。**
`lcc-external-app` は先行して作られた別リポジトリの実装であり、本書はその内容を
理解するための参考資料です。両者の設計が食い違う場合、既定では `microservices-terraform` の
`documents/terraform/*.md`・`documents/authentik/*.md` と実際の Terraform コードを優先します。

`lcc-external-app` 側には「`microservices-terraform` の該当文書を更新すること」を
承認条件・実装ゲートにしている記述が複数あります（[12.2](#122-この-repo-の文書に求められている更新) の一覧）。
**これらは向こうからの要求であって、この repo で決定済みの事項ではありません。**
本書に書いてあることを根拠に、`microservices-terraform` 側の設計や実装を勝手に書き換えないでください。

### 怪しいときは判断を仰ぐ

次に当てはまる場合は、**自分で片方に寄せて実装せず、いったん止めて人（PL・リポジトリのオーナー）に確認してください。**

| 状況 | 例 |
| --- | --- |
| 両リポジトリの設計が正面から食い違う | サービス分割、認証方式、テナントモデル（[12.1](#121-設計が食い違っている点)） |
| `lcc-external-app` が `microservices-terraform` の文書更新を前提にしている | ADR-0004 の承認条件、`05`/`08`/`14`/`16` の更新要求 |
| `microservices-terraform` 内部で記述が矛盾している | `13-operation-layers.md` の Floating IP・DNS、Credential 保管先（`14` と `16`） |
| 上位文書（要件定義書・構成仕様書）と食い違う | Bearer token の種別、公開範囲、クレジット周期 |
| 本書の記述と実ファイルが合わない | 本書は 2026-09-06 時点の要約なので、実ファイルが正 |

判断を仰ぐときは「どちらが正か」ではなく、**「どちらに寄せるか・その決定をどの文書へ書くか」**まで
決めてもらってください。片方だけ直すと矛盾が残ります。

### 鮮度

本書は **2026-09-06 時点**の `lcc-external-app`（ブランチ `feat/openstack-gateway`）を要約したものです。
向こうは活発に変更されているため、実装に着手する前に必ず原典（特に `CLAUDE.md` と
`docs/design/conformance-v030.md`）を読み直してください。
本書の記述と `lcc-external-app` の実ファイルが食い違った場合は、実ファイルが正です
（本書の写し間違い、または本書が古いということです）。

---

## 1. 何であるか

| 項目 | 内容 |
| --- | --- |
| 名前 | LC-Cloud Middle API（`lcc-external-app`） |
| 目的 | Web UI・CLI・外部アプリへ、OpenStack / Kubernetes / 認証 / 課金の違いを隠した単一の公開 API を出す |
| 言語 | Go 1.27（`labstack/echo/v5`・`pgx/v5`・`go-jose/v4`。OpenStack SDK は使わず自前 HTTP クライアント） |
| 契約 | OpenAPI 3.1。仕様から Go の型とサーバーインターフェースを生成（`oapi-codegen`） |
| ツール | `mise`（全ツールを固定）・`uv`（Python スクリプト）・`vacuum`（OpenAPI lint）・MkDocs |
| 規模 | Go 約 24,000 行、設計ドキュメント約 6,400 行 |
| 期間 | 2026-08-09 初コミット 〜 2026-09-06（合宿）。主に 1 名が実装 |
| 状態 | **開発プロファイルのみ。`LCC_ENV=production` は意図的に起動を拒否する** |

起動は `mise trust && mise install && mise run generate && mise run check && mise run serve` だけです。
既定では下流を一切呼ばず、シードした開発状態を返します。

---

## 2. 最重要: 契約が2つある

このリポジトリを読むときに最初に踏む罠です。`CLAUDE.md` が冒頭で警告しています。

| | `api/`（現行・維持する） | `api-next/`（実装対象） |
| --- | --- | --- |
| title / version | LC-Cloud Middle API 0.2.0 | LC-Cloud Infrastructure API 0.3.0 |
| base URL | `/api/v1` | `/api/infra/v1` |
| テナント | Organization 1 : OpenStack Project 1 | Team 1 : N Project |
| VM | `/orgs/{org_id}/instances` | `/projects/{project_id}/vms` |
| 電源操作 | `POST .../instances/{id}/action` | `POST .../vms/{id}/start` `/stop` `/reboot` |
| Job | `/orgs/{org_id}/jobs` | `/projects/{project_id}/jobs` と `/jobs/{id}/events` |
| 請求 | 無し（組織 = 課金単位） | `billing-accounts` の参照系（書き手は Terraform だけ） |
| Kubernetes | 5 操作あり | **対象外**。別 API として定義する |
| Go 実装 | 追従済み | 部分実装（28 操作中 23）・実機未検証。請求は 503 |

- **`api-next/` v0.3.0 が PL 承認済みの実装対象**（[PR #10]、`docs/design/api-vnext.md` が Status: Accepted）。
- `api/` v0.2.0 は既存クライアントが呼んでいる現行契約なので壊さない。
- 両方の面が**同じバイナリで同時に出ます**。共有しているのは `internal/adapters` と
  `internal/publicerr` だけで、認証もエラーハンドラーも開発用ヘッダーも面ごとに別です。
- `api/src/schemas/` と `api-next/schemas/` に**同名で定義の異なる型が 14 個**あります
  （`AuditEvent` `AuditEventList` `AuditResult` `Flavor` `HealthStatus` `Identifier` `Image`
  `Job` `JobList` `JobState` `ManagementPlane` `Principal` `Problem` `Role`）。
  型名で grep すると 2 件ヒットするので、必ずディレクトリまで確認する必要があります。

[PR #10]: https://github.com/lc-tut/lcc-external-app/pull/10

---

## 3. 公開ドメインモデル（v0.3.0）

`ADR-0004` が決めたモデルです。**所有（誰のリソースか）と課金（誰が払うか）を別の関係にします。**

```text
所有
  Principal --Membership--> Team --owns--> Project --owns--> VM / その他リソース
  Team    --ProviderBinding--> Authentik Group
  Team    --ProviderBinding--> OpenStack Project / K8s Namespace
  Project --ProviderBinding--> OpenStack Project / K8s Namespace

課金
  BillingAccount --pays for--> Team
                 --pays for--> Project
                 --attributes--> OpenStack Project / K8s Namespace（帰属であって所有ではない）
```

| 関係 | 多重度 | 規則 |
| --- | --- | --- |
| Principal - Team | 多対多 | Membership が `viewer` / `member` / `owner` を持つ |
| Team - Project | 1 対多 | Team は認可境界、Project はリソース境界 |
| Project - OpenStack Project | 1 対 1 | 内部 ProviderBinding。公開 ID や名称の一致を仮定しない |
| BillingAccount - Team / Project | 1 対 0..多 | 1 アカウントで複数 Team・Project を支援できる |
| Project - BillingAccount | 0..1 対 1 | 未設定なら所属 Team の link を使う（`link_source` で判別） |

- 公開 ID（`team_id` `project_id` `billing_account_id` `instance_id` `job_id`）は
  **LCC 発行の不透明で不変な ID**。OpenStack UUID・Namespace 名・Authentik Group ID を公開主キーにしない。
- BillingAccount を共有してもリソースの参照・操作権限は広がらない。認可は Membership と所有関係だけで決まる。
- 個人利用者には personal Team・default Project・personal BillingAccount を登録時に一括作成する。
- 構成仕様書の Guest ロールは、招待状態と resource role の責務が未分離のため Role enum に入れない。

### `microservices-terraform` の用語との対応

| このリポジトリ | 本書側 | 備考 |
| --- | --- | --- |
| `catalog/teams/<name>/` | Team | Authentik Group に対応する認可境界 |
| `catalog/projects/<name>/` | Project | OpenStack Project / K8s Namespace に対応するリソース境界 |
| VM | VM（path 上は `vms`） | schema 名と Job `kind` だけ v0.2.0 互換で `Instance` / `create_vm` |
| `/api/infra/projects/{project}/vms`（13-operation-layers.md） | `/api/infra/v1/projects/{project_id}/vms` | version segment だけ追加 |
| `infra-api` / `k8s-api` の 2 サービス | 同一 codebase の `api` / `worker` / `reconciler` | 将来分割しても公開 path は変えない |

**path 形状とリソース名は `microservices-terraform` を正としています。** 構成仕様書 v1.3 表 4-5 の
`/api/v1/orgs/{org_id}/{resource}` ではなく、`13-operation-layers.md` の形に寄せたということです。

---

## 4. エンドポイント

### v0.3.0（`/api/infra/v1`・実装対象・全 28 操作）

| Method | Path | 必要ロール |
| --- | --- | --- |
| GET | `/health/live` `/health/ready` | 不要 |
| GET | `/me` `/teams` | 認証のみ |
| GET | `/teams/{team_id}` | viewer |
| GET | `/teams/{team_id}/projects` | viewer |
| GET | `/teams/{team_id}/audit-events` | owner |
| GET | `/teams/{team_id}/billing-accounts`（一覧・詳細・`/links`） | viewer |
| GET | `/teams/{team_id}/billing-account` | viewer |
| GET | `/projects/{project_id}` | viewer |
| GET | `/projects/{project_id}/capacity` | viewer |
| GET | `/projects/{project_id}/catalog/{flavors,images,networks,security-groups}` | viewer |
| GET | `/projects/{project_id}/billing-account` | viewer |
| GET / POST | `/projects/{project_id}/vms` | viewer / member |
| GET / DELETE | `/projects/{project_id}/vms/{vm_id}` | viewer / member |
| POST | `/projects/{project_id}/vms/{vm_id}/start` `/stop` `/reboot` | member |
| GET | `/projects/{project_id}/jobs`、`/jobs/{job_id}`、`/jobs/{job_id}/events` | viewer |

Terraform だけが呼ぶ書き込み系（`PUT`/`DELETE` の billing-accounts・billing-account link・
access-grants・lifecycle-state の 10 endpoint）は設計済みですが、LCC Terraform Provider が
未実装のため OpenAPI にはまだ入っていません。

Phase 2 として path と同期／非同期方式だけ確定済みなのは、Cinder（volume CRUD・attach/detach・
resize・snapshot）、Swift（bucket・Temp URL）、Designate（レコード参照）、Trove（DB 操作）、
Manila（share）、Barbican（secret）、VM コンソール・コンソールログ・スナップショット、
クォータ増枠申請（GitHub PR を作って URL を返す）です。

### v0.2.0（`/api/v1`・現行契約・21 操作）

`/me` `/orgs` `/orgs/{id}` `/catalog/flavors` `/catalog/images` `/orgs/{id}/capacity`、
instances の一覧・作成・詳細・削除・`/action`、jobs の一覧・詳細、`/audit-events`、
Kubernetes の pods・pod logs（JSON / SSE）・deployments・rollout restart・PVC。

---

## 5. 操作の所有境界

`13-operation-layers.md` をそのまま公開契約へ写しています。ADR-0003 が根拠です。

| 対象 | 実行主体 | 公開 API の役割 |
| --- | --- | --- |
| 長期・本番 VM の作成・サイズ変更・削除 | Terraform | 状態参照のみ |
| 実験・一時 VM の作成・削除 | Middleware | クォータ・TTL を検証して Job 受付 |
| VM の起動・停止・再起動 | Middleware | Terraform 管理 VM に対しても許可 |
| network・SG・Floating IP・DNS・LB | Terraform | 参照のみ。変更 API を置かない |
| Deployment / Service / Ingress / HPA | GitOps | 宣言状態を変えず同期状態を参照 |
| Pod ログ・rollout restart | Middleware | v0.2.0 のみ。v0.3.0 では対象外 |

- `POST /vms` は `lifecycle=ephemeral` と `ttl_hours` 1〜168 だけを受け付けます。
- `DELETE` は `managed_by=middleware` だけ。Terraform 管理 VM は `409 terraform_managed_resource`。
- OpenStack 実接続では **Nova メタデータ `lcc_managed_by=middleware` が付いた VM だけを
  Middleware 所有とし、メタデータの無い VM は Terraform 管理として扱います**（付け忘れによる誤削除を防ぐ既定）。
- Middle API が作る VM には `lcc_managed_by` / `lcc_lifecycle` / `lcc_expires_at` /
  `lcc_org_id` / `lcc_owner` のメタデータが付きます。

---

## 6. 非同期 Job 契約（ADR-0005）

公開 `POST /jobs` は設けず、リソースごとの型付き endpoint から操作を開始します。

**`202 Accepted` の意味**: 「OpenStack が成功した」ではなく、次を**同一トランザクションで永続化できた**こと。

1. `provisioning` 状態の LCC Instance（create のみ）
2. `queued` 状態の Job
3. Idempotency record
4. worker dispatch 用 outbox record
5. create では quota 需要を固定した `capacity_reservations`
6. 追加消費操作では BillingAccount / link version を固定した `billing_admissions`

どれかを保存できなければ Job ID を返さず `503`。応答には `Location`（Job URL）・`Retry-After`・
`X-Trace-ID`・`ETag` が付きます。

| 項目 | 内容 |
| --- | --- |
| state | `queued` / `running` / `succeeded` / `failed` / `canceled`（closed enum。分岐にはこれだけ使う） |
| phase | `accepted` → `resolving_bindings` → `preparing_network` → … → `completed`。open enum |
| 結果不明時 | `running` / `reconciling` のまま mutation lock を保持。証拠なく `failed` にしない |
| 成功条件 | Provider の 202/201 では成功にしない。Nova ACTIVE + `task_state=null` + port 一致まで確認 |
| 削除の成功条件 | DELETE 204 ではなく **owner GET が 404** になること（`reclaim_instance_interval` 対策） |
| event | `/jobs/{id}/events?after_sequence=` で増分取得 |
| cancel | MVP では公開しない |
| キュー | asynq（Redis）。DB `outbox` は asynq への enqueue を DB commit と原子的にするための表 |
| Job の正 | PostgreSQL の `jobs` / `job_events`。Redis 喪失で Job は消えない |

冪等性は `Idempotency-Key`（`[A-Za-z0-9._:-]{16,128}`）を必須とし、
`UNIQUE(subject, team_id, scope_kind, scope_id, key)` で管理します。
同じキーで body が違えば `409 idempotency_key_reused`。fingerprint は
server default 解決**前**の client intent から作るので、初回後に Project default が変わっても
replay が別リソースを作りません。保持期間は非同期操作 30 日、同期系 24 時間。

### TTL 回収

`ephemeral` は「期限が来たら消える」契約なので、期限切れ VM を回収するスケジューラーがあります。

- `expiry_claims` を PostgreSQL に持ち、row lock と lease で多重起動を防ぐ
- actor は `system:ttl-controller`、冪等キーは `ttl-expiry:{instance_id}:{expires_at}` で決定的
- 削除直前に所有を再確認する（claim 後に Terraform 管理へ付け替えられた VM は消さない）
- 確認できなければ claim を開いたまま残し、次の走査で再試行する（失敗を「削除済み」で閉じない）
- 利用者 delete が先行していればその Job へ claim を関連付け、新 Job を作らない

---

## 7. OpenStack 実行設計

### 呼び出し順序（VM 作成）

1. Project ProviderBinding から Keystone scope・service catalog・Application Credential を解決
2. **Neutron で LCC 所有 port を事前作成**し marker を付け、Nova には network UUID ではなく
   **port UUID** を渡す（部分失敗時に attachment の所有者を特定できるようにするため）
3. `root_volume` なしは Nova image boot
4. `root_volume` ありは Cinder volume → BDMv2（`boot_index=0`, `delete_on_termination=true`）
5. Nova create に name / flavor / port / boot source / marker だけを送る
   （AZ・keypair・user_data・scheduler hint は公開 API で受けていないので補完しない）
6. 各受付直後に external ID と Provider 応答相関を永続化してから次工程へ進む

**応答喪失時は marker 検索で照合し、盲目的に再送しません。** marker 検索が 0 件でも
「Provider が受け付けていない」証拠とは扱わず、`reconciling` と mutation lock を維持します。

### 公開値の変換

| 公開値 | 内部解決 | 下流 |
| --- | --- | --- |
| `project_id` | Project ProviderBinding | Keystone scope / Application Credential |
| `flavor_id` / `image_id` | CatalogBinding | Nova flavor UUID / Glance image UUID |
| `network_id`・`security_group_ids` | Project allowlist | Neutron UUID |
| `ttl_hours` | LCC expiry policy | 下流へ送らない |

### read の正本（設計）

read API は保存済み observation だけを読み、Provider へ同期接続するのは **mutation 受付時の 1 回だけ**、
という設計です。fresh 30 秒 / stale 5 分 / Catalog 10 分。stale なら `freshness=stale` と
`observed_at` を返し、事実を隠しません。**現実装はこの点が未達で、read のたびに Provider を叩いています。**

### capability

`capabilities` は **Project と adapter の実行可能性**であって呼び出し元の権限ではありません。
満たせない操作は受付時に `409 capability_unavailable` で断ります。v1 の条件は
「Kolla-Ansible で構築した素の OpenStack で成立する最小条件」に引き下げてあり、
microversion 2.69 や Neutron tag、`reclaim_instance_interval=0` の attestation などの
強化条件は Phase 1.1 送りです。

---

## 8. 認証・認可

- API Bearer は **Authentik 発行の OAuth 2.0 access token**。ID token は API Bearer に使わない
  （構成仕様書 表 4-5 の `oidc_id_token` からの意図的な差分。`aud` 検証が成立しないため）。
- JWKS で署名を検証し `iss` `aud` `exp` `nbf` を検証。JWKS は最大 5 分キャッシュ、未知 kid で再取得。
- Authentik 2026.5.6 は access token と ID token の**両方に `typ=JWT`** を使うため、
  `typ` では識別できず、署名検証後に access token 固有の `azp` / `uid` / `lcc:infra` scope を要求する。
- **権限の正は JWT の claim ではなく PostgreSQL の `directory_principals` / `directory_memberships`**。
  `issuer + sub` から内部 Principal ID を解決し、毎回 DB から現在の所属を取る。
- 利用者トークンを OpenStack へ転送しない。Project スコープの Application Credential を
  サーバー側で取得する（`ADR-0002`）。
- 開発モードはヘッダー認証（`X-LCC-Dev-User` + `X-LCC-Dev-Organizations`（v0.2.0）/
  `X-LCC-Dev-Teams`（v0.3.0））。loopback にしか bind せず、片方のヘッダーで他方を呼ぶと 401。
- `LCC_AUTH_MODE=oidc` では v0.2.0 の保護操作を 401 にし、開発ヘッダーによる迂回を塞ぐ。

権限表:

| 操作 | viewer | member | owner | Terraform |
| --- | :---: | :---: | :---: | :---: |
| Team / Project / VM / Job 参照 | yes | yes | yes | yes |
| VM 作成・削除・電源操作 | no | yes | yes | no |
| BillingAccount・grant・link の参照 | yes | yes | yes | yes |
| BillingAccount の upsert・close、link 変更、grant、suspend | no | no | no | yes |

**BillingAccount の書き込みはロールではなく呼び出し元の種別で決まります。**
利用者トークンでは owner でも `403 terraform_managed_resource` です。
Terraform principal は GitHub Actions OIDC トークンで認証し、`repository` と `workflow_ref` を
workspace registry の登録内容と照合します。

---

## 9. 請求アカウント（この repo に直接効く話）

```text
定義・レビュー          書き込み            正            参照
PR + CODEOWNERS  ->  Terraform apply  ->  Middle API  ->  control-plane DB
                        (LCC Provider)         ^
                                               |
                       Web UI / CLI / 他システム（GET のみ）
```

- **Terraform が唯一の書き手、control-plane DB が正、経路は本 API**。
  Terraform は DB や CloudKitty を直接触らず、Middle API の mutation endpoint を叩きます。
- 利用者向けの作成・変更・close は設けません。Web UI から作れると PR と CODEOWNERS の
  承認を迂回できてしまうためです。
- `POST` ではなく `PUT` の upsert。ID は Terraform 側が `team-web` のような安定キーから決め、
  サーバーは採番しません。`If-Match`（初回は `If-None-Match: *`）で楽観ロックします。
- `DELETE` は物理削除ではなく `closed` への遷移。ID・link 履歴・監査は残ります。
  current link が残っていれば `409 billing_account_in_use`。
- `GET .../billing-accounts/{id}/links` **だけ**が例外的に Provider 固有 ID
  （`openstack_project_id` と `kubernetes_namespace`）を返します。課金の突き合わせが
  Provider ID でしかできないためです。認証情報・endpoint URL は返しません。
- **必要な Terraform Provider リソース**: `lccloud_billing_account` と
  `lccloud_project_billing_account`。Provider が無い間は請求アカウントを作れないため、
  Middle API の billing endpoint と Provider リソースは同じ Phase で実装する前提です。

これは `08-billing.md` の「デフォルトから変更したい場合のみ `catalog/billing-accounts/` に
ファイルを追加」という運用と両立しますが、**デフォルトのアカウント自体も team モジュールが
PUT で作って Terraform state に載せる**点が現行の設計と違います。

---

## 10. 実装状況（2026-09-06 時点）

`LCC_BACKEND` でバックエンドを選びます。

| 値 | 内容 |
| --- | --- |
| `memory`（既定） | 両方の面をシード実装が満たす。下流不要。TTL 回収も動く。**返す値はどれも Provider 由来ではない** |
| `openstack` | 両方の面が実 OpenStack。Kubernetes は 503。v0.3.0 の Job・冪等性・監査・TTL claim・Provider 相関は PostgreSQL（`LCC_DATABASE_URL` 必須）。v0.2.0 の Job・監査はメモリのまま |

### 動くもの

- Keystone v3 Application Credential 認証、トークンキャッシュ、カタログからの endpoint 解決
- Nova のフレーバー・サーバー一覧／詳細／作成／削除／start・stop・reboot
- Glance イメージ一覧、Neutron ネットワーク・SG 参照、Nova / Cinder / Neutron のクォータ観測
- Terraform 管理 VM の破壊防止、TTL 回収（PostgreSQL claim・再起動をまたいで継続）
- Authentik OIDC のローカル実接続検証（署名・iss・aud・exp・nbf、JWKS 交代、ID token の 401）
- PostgreSQL の control-plane DB（`jobs` `job_events` `idempotency_records` `outbox`
  `resource_bindings` `provider_operations` `capacity_admission` `capacity_reservations`
  `expiry_claims` `audit_events` `target_locks` `directory_*`）

### 動かないもの・設計未達（`docs/design/conformance-v030.md` に全件）

| 項目 | 状態 |
| --- | --- |
| **v0.3.0 での VM 作成** | `capabilities.compute.create_ephemeral_vm = false`。**409 で作成できない**。作成は v0.2.0 の `/api/v1` を使う |
| read 経路 | 設計は「保存済み observation を読む」だが、実装は read のたびに Provider を同期で叩く |
| `worker` / `reconciler` プロセス | 無い。`api` のみ。asynq への enqueue も無い |
| ResourceBinding / CatalogBinding | 無い。公開 ID に Nova UUID を埋めている（`ins-<UUID>`） |
| 請求 | `503 billing_not_connected`。control-plane DB も Terraform 経路も無い |
| クレジット | credit ledger が無いため `enforced:false` と null を返す（**0 を捏造しない**） |
| cursor 型一覧 | `next_cursor` を返していない。`limit` も未対応 |
| Job の `ETag` / `304`、rate limit | 無い |
| Kubernetes ゲートウェイ | 未接続。`kubernetes` capability は memory バックエンドでのみ |
| v0.3.0 の実機検証 | 有効な Application Credential で一度も通していない |
| TLS・メトリクス・3 年監査保持 | 無い |

`LCC_ENV=production` は上記が揃うまで起動を拒否します。

---

## 11. ADR 一覧

| ADR | 内容 | Status |
| --- | --- | --- |
| 0001 | 設計情報源と旧一覧の扱い（承認済み ADR と OpenAPI を正とする） | Proposed |
| 0002 | 単一公開 API と下流アダプター（下流の分割・URL を公開しない） | Proposed |
| 0003 | Terraform・GitOps・Middleware の操作境界 | Proposed |
| 0004 | Team・Project・BillingAccount と下流マッピング | **Accepted** |
| 0005 | 型付き操作と観測可能な非同期 Job | **Accepted** |
| 0006 | OpenAPI を外部契約の正とする | Proposed |
| 0007 | クレジット周期・枯渇時ポリシーの相違を公開モデルで保持 | Proposed |

ADR-0007 は、要件定義書 p.20 の「年次付与・繰越なし・枯渇時は新規停止＋既存 VM 強制停止」と
`13-operation-layers.md` 系の「月次リセット・新規作成ブロック」が食い違うため、
公開 API では周期を `monthly|annual`、枯渇時ポリシーを `block_new|block_new_and_stop` として
**両方を表現できる形にして値を固定しない**という決定です。

---

## 12. `microservices-terraform` 側への影響

ここが本書を置いた主目的です。向こうの設計は、この repo の文書を更新することを前提にしています。

### 12.1 設計が食い違っている点

| 論点 | `microservices-terraform` の記述 | `lcc-external-app` の結論 |
| --- | --- | --- |
| サービス分割 | `14-middleware-architecture.md`: infra-api / billing-api / k8s-api の 3 サービス | 同一 codebase・単一バイナリを `api` / `worker` / `reconciler` の 3 process mode で起動。将来分割しても公開 path は変えない |
| 認証 | `14`: Authentik Outpost の forward-auth に委譲し `X-authentik-*` ヘッダーを信頼 | API 自身が access token の署名・claim を検証し、権限は control-plane DB の Membership から取る |
| テナント | 構成仕様書 用語定義(6): 組織 = OpenStack Project / Namespace / Authentik Group に 1:1 | Team（認可境界）1:N Project（リソース境界）。ADR-0004 |
| 認可判定 | `14`: Vault の `kv/app-creds/{project}.team_name` を読んで判定 | DB の Membership と Team/Project 所有関係だけで判定 |
| 請求アカウント | `14`: billing-api が独自 DB を持ち、`restapi` プロバイダー経由で Terraform が叩く | 方向は同じ。ただし単一 API に統合し、`billing_admin` ロールと `X-LCC-Admin-Reason` は廃止 |
| Kubernetes | `14`: k8s-api として同居 | v0.3.0 の対象外。別 API として後日定義 |
| Credential 保管 | `14`: Vault ／ `16-implementation-phases.md` [P1]: Vault 非導入・GitHub Secrets | CI/CD 用 = GitHub Actions Secret、Middleware runtime / observer 用 = Vault、に分離 |

### 12.2 この repo の文書に求められている更新

ADR-0004 と `api-vnext.md` の承認条件・ゲートに明記されているものです。

1. **`05-project-lifecycle.md`・`08-billing.md`・`14-middleware-architecture.md`・
   `16-implementation-phases.md` を ADR-0004 と同じ版で更新するか superseded 表示する。**
   残すと、旧 one-phase archive、Account 状態の Terraform writer、Account 単位 quota/budget 継承、
   Vault / GitHub Secrets の矛盾が実装入力として残ってしまうため。
2. **Team / Project の用語を ADR-0004 の定義（Team 1:N Project）へ揃える。**
3. **`catalog/billing-accounts/` 案を MVP runtime から外し、Project quota と Account link を分離する。**
   Project quota と Provider resource policy の desired state は Project 単位の Terraform state が持ち、
   BillingAccount link から継承しない。
4. **`13-operation-layers.md` の矛盾を PL が確定する。** 同一文書内で
   Floating IP（レイヤー表は Terraform ✅／endpoint 設計概要には `POST /floatingips/{id}/associate` がある）と
   DNS レコード（同様）が食い違っています。`lcc-external-app` はレイヤー表を正とし、
   Middleware API には置かない（参照のみ）と決めています。
5. **Credential 保管先の記述を統一する。** `14` の Vault と `16` [P1] の「Vault 非導入」が矛盾。
   CI 用 GitHub Actions Secret は要件定義書 4.6 / 5.4 の [Must] に対する部分例外として承認が要る。
6. **外部公開範囲。** 構成仕様書 p.62 は社内 DNS のみ・外部非公開、`14` は Internet → External LB の図。
   `lcc-external-app` は承認が無い限り構成仕様書の社内限定を上位制約として扱っています。
7. **`catalog/projects/_template` への追加。** `14` の記述と同じく、`team_name` を
   `team_project_id` とは別の入力変数として追加し、apply 時に Vault へ
   `app_cred_id` / `app_cred_secret` / `team_name` を書く処理が要ります。
8. **LCC Terraform Provider の実装。** `lccloud_billing_account` /
   `lccloud_project_billing_account` が無いと請求アカウントを作れません。
9. **二段階 archive handshake**（prepare → destroy → finalize の server-side verifier）を
   Project archive の手順として合意する。

### 12.3 この repo 側が満たすべき前提

| 前提 | 現状（`16-implementation-phases.md` 基準） |
| --- | --- |
| Phase 3 OpenStack platform | ✅ 実機適用済み |
| Phase 4 catalog（teams / projects） | ✅ E2E 検証済み。ただし GitHub Actions Secret 自動登録は未実装 |
| Phase 6 Middleware API | この repo は未着手。`lcc-external-app` が先行して実装している |
| CloudKitty | Hashmap ルールは実装済み。「Organization / 予算」は自前実装が未着手 → `credits` が null のまま |
| Designate / Octavia | 実機 Polaris 未導入 → DNS・LB 系 endpoint は Phase 2 のまま |

---

## 13. ファイルの地図

```text
apps/lcc-external-app/
├── CLAUDE.md                 作業前に必ず読む。2契約の違いと同名型14個の警告
├── AGENTS.md                 CLAUDE.md へのポインタ
├── README.md                 起動手順・合宿到達点・管理境界
├── api/                      現行契約 v0.2.0（維持する）
│   ├── src/                  編集元（分割）。ここを直して mise run bundle
│   └── openapi.yaml          生成物
├── api-next/                 実装対象 v0.3.0
│   ├── paths/ schemas/ components/   編集元
│   └── openapi.bundled.yaml  生成物
├── internal/
│   ├── publicerr/            両面が公開するエラー語彙。何にも依存しない
│   ├── controlplane/         v0.2.0 のドメイン（6ポート）
│   ├── infraplane/           v0.3.0 のドメイン
│   ├── adapters/
│   │   ├── memory/           シード実装
│   │   ├── openstack/        実 OpenStack（両面のポートを1つの Keystone session で満たす）
│   │   ├── postgres/         control-plane DB（migrations 3本）
│   │   ├── authentik/        access token verifier
│   │   └── unavailable/      未接続の下流を 503 として明示
│   ├── httpapi/ infraapi/    各面の HTTP 変換・生成コード
│   └── app/                  DI とルーティング（両面をマウント）
├── docs/
│   ├── adr/                  0001〜0007
│   ├── design/api-vnext.md   **実装方針の正**（約2,200行）
│   ├── design/conformance-v030.md  設計への追従状況を全件記録
│   ├── design/api-vnext-internal.md  Status: Deferred。実装入力にしない
│   ├── design/camp-mvp.md    historical baseline。実装入力にしない
│   ├── api/                  v0.2.0 のリファレンス（呼ぶ人向け）
│   ├── operations/           openstack.md / authentik.md / verification.md
│   └── reference/legacy-*.md 旧機能候補（281件）。実装対象ではない
├── scripts/                  Authentik セットアップ・疎通確認（Python / uv）
└── mise.toml                 全タスク定義
```

依存方向は `.golangci.yml` の depguard が強制します。`controlplane` と `infraplane` は
HTTP を import できず、`httpapi` と `infraapi` は具体アダプターを import できず、
**2つの面は互いを import できません。**

生成物（`api/openapi.yaml`、`api-next/openapi.bundled.yaml`、
`internal/{httpapi,infraapi}/openapi.gen.go`）は直接編集せず、`mise run check` が差分を検出します。

---

## 14. 読むときの注意

- `docs/design/api-vnext-internal.md` は Status: Deferred。Credential rotation と内部 Terraform API の
  草案で、**実装入力にしない**と明記されています。
- `docs/design/camp-mvp.md` は v0.2.0 開発プロファイルの historical baseline です。
- `docs/reference/legacy-*.md` は再設計前の機能候補一覧（281 件）で、
  件数や優先度が書かれていてもそれだけで実装対象にはなりません。
- `api/openapi.yaml` と `api-next/` が食い違う説明を見つけたら、OpenAPI が正です。
- 「Mock や OpenAPI が存在すること」を実装完了として扱わない、というのが向こうの一貫した姿勢です。
  実装が設計に届かないときは注意書きではなく **capability を false にして 409 で断る**方針です。
