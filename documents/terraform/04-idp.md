# IdP 設定（Authentik）

## 概要

Authentik は LinuxClub の Identity Provider（IdP）です。
すべてのメンバーアカウント・グループ・SSO・入会フローを一元管理します。

Terraform での管理には
[goauthentik/terraform-provider-authentik](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs)
を使用します。別途 image や独自 provider は不要です。

`terraform/platform/idp/` は「Authentik に何を設定するか」（flow / stage / brand /
group 等）を宣言します。**Authentik インスタンスそのもの**（VM・コンテナ）を
本番 OpenStack 環境に構築するのは `terraform/platform/infra/idp-infra/` です
（詳細・実機構成は同ディレクトリの README 参照）。`idp/` の `authentik_url` /
`authentik_token` には `idp-infra` の `terraform output` の値を渡します。
ローカル開発では `local/authentik/` の Docker Compose 版を使います
（`15-local-development.md`）。

実際の `terraform/platform/idp/` はサブディレクトリの無いフラット構成で、
ファイル名のプレフィックスで役割を表します（後述のコード例のパスコメントも
これに合わせて読んでください）。このドキュメントで扱う核となるファイルは以下です
（`annual_renewal.tf`・`authentication.tf`・`brand.tf`・`provider_discord_source.tf` 等、
このドキュメント作成後に追加されたファイルは `documents/authentik/` 側を参照してください）。

```text
terraform/platform/idp/
├── main.tf                    # provider 設定・共通 data source
├── variables.tf
├── recovery.tf                 # パスワードリセット／初回ウェルカムフロー（入会時の
│                              #   username・パスワード設定もここで行う。下記「入会フロー」参照）
├── provider_lc_cloud.tf        # LC-Cloud OIDC プロバイダ（フェデレーション認証）
├── provider_github_source.tf   # GitHub OAuth Source（任意連携）
├── policy_username.tf          # username バリデーションポリシー
├── notification_transports.tf  # Webhook・メール送信設定
└── notification_rules.tf       # 通知トリガールール
```

---

## Provider 設定

```hcl
# main.tf
terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.10"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
```

```hcl
# variables.tf
variable "authentik_url" {
  type    = string
  default = "https://auth.lc-cloud.example.internal"
}

variable "authentik_token" {
  type      = string
  sensitive = true
}

variable "github_oauth_client_id" {
  type = string
}

variable "github_oauth_client_secret" {
  type      = string
  sensitive = true
}

variable "webhook_secret" {
  type      = string
  sensitive = true
  description = "GitHub Actions repository_dispatch の HMAC シークレット"
}
```

---

## 入会フロー（enrollment flow）

**このセクションが記述していた `enrollment.tf`（招待コード制の独立 Flow）は
2026-08-31 に削除しました。** `authentik_invitation` を発行する仕組みがどこにも無く、
`brand.flow_enrollment` にも設定されておらず、実際に新入会員が通る経路ではなかったためです。

実際の入会は、Terraform が `members_secrets.yaml.enc` の内容から直接 `authentik_user` を
作成し（パスワード未設定の状態）、`recovery.tf` の「ようこそ」Flow 経由で本人に
username・パスワードを設定してもらう方式です。詳細は
[`documents/authentik/forms/01-enrollment.md`](../authentik/forms/01-enrollment.md) と
[`documents/authentik/02-membership-lifecycle.md`](../authentik/02-membership-lifecycle.md) を
参照してください。

---

## username バリデーションポリシー

```hcl
# policy_username.tf
resource "authentik_policy_expression" "username_rules" {
  name       = "enrollment-username-rules"
  expression = <<-PYTHON
    import re
    username = request.context.get("prompt_data", {}).get("username", "")
    if not re.fullmatch(r"[a-z][a-z0-9\-]{2,30}", username):
      ak_message("ユーザー名は半角英小文字で始まり、英小文字・数字・ハイフンのみ使用可（3〜31文字）")
      return False
    from authentik.core.models import User
    if User.objects.filter(username=username).exists():
      ak_message("このユーザー名はすでに使われています")
      return False
    return True
  PYTHON
}
```

---

## 全メンバーグループ

```hcl
# main.tf（続き）
resource "authentik_group" "all_members" {
  name         = "all-members"
  is_superuser = false
}
```

---

## GitHub OAuth Source（任意連携・ログインにも使用可）

GitHub アカウント連携は任意です。連携済みのメンバーは GitHub アカウントでの
ログインにも使えます（ログイン flow は後述の「ログイン flow のカスタマイズ」参照）。
一方 `enrollment_flow` は `null` のままにしており、GitHub 認証だけで
未連携ユーザーが新規アカウントを作ることはできません
（新規アカウントは Terraform が `members_secrets.yaml.enc` を起点に直接作成する方式のみ。
上の「入会フロー」節参照）。

```hcl
# provider_github_source.tf
resource "authentik_source_oauth" "github" {
  count = var.github_oauth_client_id != "" ? 1 : 0

  name          = "GitHub"
  slug          = "github"
  provider_type = "github"

  consumer_key    = var.github_oauth_client_id
  consumer_secret = var.github_oauth_client_secret

  # 既に連携済みのメンバーはログインに使える
  # （authentication_id.sources に登録。下記「ログイン flow のカスタマイズ」参照）
  authentication_flow = authentik_flow.lc_cloud_authentication.uuid
  enrollment_flow     = null

  user_matching_mode = "identifier"
}
```

連携操作はメンバーが Authentik の「Connected Sources」画面から任意で行います。
連携完了時に `source_linked` イベントが発火し、
Webhook 経由で `auto-gen-github-usernames.yaml` が自動更新されます
（詳細は `03-member-management.md` 参照）。

Discord OAuth Source も同じ方針（`authentication_flow` はログイン flow、
`enrollment_flow` は `null`）で設定しています。詳細は
[`documents/authentik/04-discord-integration.md`](../authentik/04-discord-integration.md) 参照。

---

## ログイン flow のカスタマイズ

Authentik が自動生成する組み込みの `default-authentication-flow`
（title 固定で "Welcome to authentik!"）は blueprint 管理下のオブジェクトのため、
Terraform では直接編集しません（blueprint 再適用時に上書きされる可能性があるため）。
代わりに独自のログイン flow `lc-cloud-authentication` を作成し、
`authentik_brand.default.flow_authentication` で差し替えています
（`terraform/platform/idp/authentication.tf`）。

- ステージ構成は組み込み flow と同じ（identification → password →
  MFA検証 → user_login の4ステージ）で、title だけ "Welcome to LC-Cloud!" に変更
- `authentik_stage_identification` の `user_fields` は
  `["email", "username", "upn"]`。`"upn"` は `attributes.upn` を照合対象にする
  Authentik の特別なキーで、将来メンバーに独自ドメインのメールアドレスを
  支給した場合に、大学メールと並行してログインに使えるようにするための受け口
  （現時点では `attributes.upn` は誰にも設定していないため無害）
- `sources` に GitHub/Discord source（設定されていれば）を含め、
  連携済みメンバーはログインページにそのまま SSO ボタンとして表示される

Brand（ログイン画面のロゴ・favicon・背景画像・タイトル）のカスタマイズは
`16-implementation-phases.md` の Phase 2 実装内容を参照。

---

## Webhook トランスポート

実際の `notification_transports.tf` / `notification_rules.tf` では、GitHub リポジトリの
owner/name を `var.github_repo_owner`/`var.github_repo_name` から組み立て、
`var.webhook_secret` が空なら全リソースを `count = 0` にして作らない
（`local.webhook_enabled = var.webhook_secret != ""`）という条件付き構成になっています。
以下のコード例では説明簡略化のため `count` を省略しています。

### enrollment 完了通知（→ auto-gen-members.yaml 更新）

```hcl
# notification_transports.tf
resource "authentik_event_transport" "enrollment_webhook" {
  name = "enrollment-completed-webhook"
  mode = "webhook"

  webhook_url          = "https://api.github.com/repos/${var.github_repo_owner}/${var.github_repo_name}/dispatches"
  webhook_mapping_body = authentik_property_mapping_notification.enrollment_payload.id
  send_once            = false
}

resource "authentik_property_mapping_notification" "enrollment_payload" {
  name       = "enrollment-dispatch-payload"
  expression = <<-PYTHON
    return {
      "event_type": "authentik-enrollment-completed",
      "client_payload": {
        "username":      notification.event.context.get("model", {}).get("username", ""),
        "display_name":  notification.event.context.get("model", {}).get("name", ""),
        "email":         notification.event.context.get("model", {}).get("email", ""),
      }
    }
  PYTHON
}
```

### GitHub 連携変更通知（→ auto-gen-github-usernames.yaml 更新）

```hcl
resource "authentik_event_transport" "github_link_webhook" {
  name = "github-source-linked-webhook"
  mode = "webhook"

  webhook_url          = "https://api.github.com/repos/${var.github_repo_owner}/${var.github_repo_name}/dispatches"
  webhook_mapping_body = authentik_property_mapping_notification.github_link_payload.id
  send_once            = false
}

resource "authentik_property_mapping_notification" "github_link_payload" {
  name       = "github-link-dispatch-payload"
  expression = <<-PYTHON
    event_type = notification.event.action  # source_linked or source_unlinked
    return {
      "event_type": f"authentik-{event_type}",
      "client_payload": {
        "username":          notification.event.user.get("username", ""),
        "source":            notification.event.context.get("source", {}).get("slug", ""),
        "github_identifier": str(notification.event.context.get("identifier", "")),
      }
    }
  PYTHON
}
```

---

## 通知ルール

```hcl
# notification_rules.tf

# enrollment 完了 → auto-gen-members.yaml 更新 Webhook
resource "authentik_event_rule" "enrollment_completed" {
  name              = "enrollment-completed"
  transports        = [authentik_event_transport.enrollment_webhook.id]
  severity          = "notice"
  destination_group = authentik_group.all_members.id

  # model_created: authentik_core.user のみ対象
}

resource "authentik_policy_event_matcher" "enrollment_event" {
  name   = "match-enrollment-model-created"
  action = "model_created"
  model  = "authentik_core.user"
}

resource "authentik_policy_binding" "enrollment_rule_policy" {
  target = authentik_event_rule.enrollment_completed.id
  policy = authentik_policy_event_matcher.enrollment_event.id
  order  = 0
}

# GitHub source_linked / source_unlinked → auto-gen-github-usernames.yaml 更新
resource "authentik_event_rule" "github_source_change" {
  name       = "github-source-change"
  transports = [authentik_event_transport.github_link_webhook.id]
  severity   = "notice"
  destination_group = authentik_group.all_members.id
}

resource "authentik_policy_event_matcher" "source_linked_event" {
  name   = "match-source-linked"
  action = "source_linked"
}

resource "authentik_policy_event_matcher" "source_unlinked_event" {
  name   = "match-source-unlinked"
  action = "source_unlinked"
}

resource "authentik_policy_binding" "source_linked_rule" {
  target = authentik_event_rule.github_source_change.id
  policy = authentik_policy_event_matcher.source_linked_event.id
  order  = 0
}

resource "authentik_policy_binding" "source_unlinked_rule" {
  target = authentik_event_rule.github_source_change.id
  policy = authentik_policy_event_matcher.source_unlinked_event.id
  order  = 1
}
```

---

## LC-Cloud へのユーザー同期（OIDC フェデレーション）

標準 Keystone には SCIM エンドポイントが存在しないため、
SCIM ではなく **OIDC フェデレーション** を使います。
Authentik がユーザーの唯一の管理元となり、Keystone にユーザーレコードをコピーしません。

```text
ユーザーが LC-Cloud にアクセス
  → Keystone が Authentik（OIDC）にリダイレクト
  → Authentik で認証完了
  → Keystone が Authentik のグループ情報を受け取り、
    federation mapping でプロジェクトロールを自動付与
```

Keystone 側では federation mapping を設定します（Terraform 管理対象外・OpenStack 管理者が設定）。

```text
# Keystone federation mapping の例
Authentik グループ "team-web" → Keystone プロジェクト "web" の member ロール
Authentik グループ "all-members" → 全プロジェクトの reader ロール
```

`providers/lc_cloud.tf` の OIDC プロバイダが認証の入り口を担います（前セクション参照）。

---

## LC-Cloud SSO プロバイダ（OIDC）

```hcl
# providers/lc_cloud.tf
resource "authentik_provider_oauth2" "lc_cloud" {
  name               = "LC-Cloud"
  client_id          = var.lc_cloud_oidc_client_id
  client_secret      = var.lc_cloud_oidc_client_secret
  authorization_flow = data.authentik_flow.default_authorization.id

  redirect_uris = [
    "https://horizon.lc-cloud.example.internal/auth/callback",
    "https://keystone.lc-cloud.example.internal/v3/OS-FEDERATION/protocols/openid/auth",
  ]

  property_mappings = data.authentik_property_mapping_provider_scope.all.ids
}

resource "authentik_application" "lc_cloud" {
  name              = "LC-Cloud"
  slug              = "lc-cloud"
  protocol_provider = authentik_provider_oauth2.lc_cloud.id
  meta_icon         = "https://lc-cloud.example.internal/favicon.ico"
}

data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_property_mapping_provider_scope" "all" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}
```

---

## enrollment フローの全体像

```text
管理者が members_secrets.yaml.enc に email + student_id + role を追加
  │
  └─ terraform apply
       │
       └─ authentik_user が is_active=false・パスワード未設定で直接作成される
            │
            └─ 「LinuxClubへようこそ」メールが送信される（member-recovery Flow 経由）
                 │
                 └─ メンバーがリンクを受け取り、ブラウザで開く
                      │
                      ├─ ようこそ案内（初回のみ。pending_user 済みなので
                      │   identification はスキップされる）
                      ├─ username 入力（本人がここで決める）
                      ├─ パスワード設定
                      └─ GitHub/Discord連携のご案内（初回のみ）
                           │
                           └─ model_created イベント発火
                                └─ Webhook → GitHub Actions（authentik-dispatch.yml）
                                     └─ auto-gen-members.yaml に username をキーで書き込み
```

---

## 関連ドキュメント

- `03-member-management.md` — members_secrets.yaml.enc・auto-gen ファイルの詳細
- `10-roles-and-permissions.md` — ロール定義と権限マトリクス
