# IdP 設定（Authentik）

## 概要

Authentik は LinuxClub の Identity Provider（IdP）です。
すべてのメンバーアカウント・グループ・SSO・入会フローを一元管理します。

Terraform での管理には
[goauthentik/terraform-provider-authentik](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs)
を使用します。別途 image や独自 provider は不要です。

```text
terraform/platform/idp/
├── main.tf              # provider 設定・共通 data source
├── variables.tf
├── flows/
│   ├── enrollment.tf    # 入会フロー（username 自己設定）
│   └── recovery.tf      # パスワードリセットフロー
├── providers/
│   ├── lc_cloud.tf      # LC-Cloud OIDC プロバイダ（フェデレーション認証）
│   └── github_source.tf # GitHub OAuth Source（任意連携）
├── policies/
│   └── username.tf      # username バリデーションポリシー
└── notifications/
    ├── transports.tf    # Webhook・メール送信設定
    └── rules.tf         # 通知トリガールール
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

ユーザーが招待リンクを踏んだ後に自分で `username` と `display_name` を設定します。
`email` は招待リソース（`authentik_invitation`）の `fixed_data` で事前に埋め込まれます。

```hcl
# flows/enrollment.tf

# フロー本体
resource "authentik_flow" "enrollment" {
  name        = "Member Enrollment"
  slug        = "member-enrollment"
  title       = "LinuxClub メンバー登録"
  designation = "enrollment"
  layout      = "stacked"
}

# ステージ 1: 招待コード検証
resource "authentik_stage_invitation" "verify" {
  name                      = "enrollment-invitation-verify"
  continue_flow_without_invitation = false
}

# ステージ 2: username・display_name・パスワード入力
resource "authentik_stage_prompt" "user_info" {
  name = "enrollment-user-info"

  fields = [
    authentik_stage_prompt_field.username.pk,
    authentik_stage_prompt_field.display_name.pk,
    authentik_stage_prompt_field.password.pk,
    authentik_stage_prompt_field.password_repeat.pk,
  ]

  validation_policies = [
    authentik_policy_expression.username_rules.pk,
  ]
}

resource "authentik_stage_prompt_field" "username" {
  field_key   = "username"
  label       = "ユーザー名（LC-Cloud ID）"
  type        = "text"
  placeholder = "例: alice（半角英小文字・数字・ハイフン）"
  required    = true
  order       = 100
}

resource "authentik_stage_prompt_field" "display_name" {
  field_key   = "name"
  label       = "表示名"
  type        = "text"
  placeholder = "例: Alice Yamada"
  required    = true
  order       = 200
}

resource "authentik_stage_prompt_field" "password" {
  field_key = "password"
  label     = "パスワード"
  type      = "password"
  required  = true
  order     = 300
}

resource "authentik_stage_prompt_field" "password_repeat" {
  field_key = "password_repeat"
  label     = "パスワード（確認）"
  type      = "password"
  required  = true
  order     = 400
}

# ステージ 3: ユーザー書き込み
resource "authentik_stage_user_write" "write" {
  name                       = "enrollment-user-write"
  user_creation_mode         = "always_create"
  create_users_as_inactive   = false
  create_users_group         = authentik_group.all_members.pk
}

# ステージ 4: ログイン
resource "authentik_stage_user_login" "login" {
  name = "enrollment-user-login"
}

# フローバインディング（ステージの順序）
resource "authentik_flow_stage_binding" "verify" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_invitation.verify.id
  order  = 10
}

resource "authentik_flow_stage_binding" "user_info" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_prompt.user_info.id
  order  = 20
}

resource "authentik_flow_stage_binding" "write" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_user_write.write.id
  order  = 30
}

resource "authentik_flow_stage_binding" "login" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_user_login.login.id
  order  = 40
}
```

---

## username バリデーションポリシー

```hcl
# policies/username.tf
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

## GitHub OAuth Source（任意連携）

GitHub アカウント連携は任意です。ログイン用ではなく「アカウント紐づけ」専用として設定します。

```hcl
# providers/github_source.tf
resource "authentik_source_oauth" "github" {
  name          = "GitHub"
  slug          = "github"
  provider_type = "github"

  consumer_key    = var.github_oauth_client_id
  consumer_secret = var.github_oauth_client_secret

  # ログインには使わない（紐づけ専用）
  authentication_flow = null
  enrollment_flow     = null

  user_matching_mode = "identifier"
}
```

連携操作はメンバーが Authentik の「Connected Sources」画面から任意で行います。
連携完了時に `source_linked` イベントが発火し、
Webhook 経由で `auto-gen-github-usernames.yaml` が自動更新されます
（詳細は `03-member-management.md` 参照）。

---

## Webhook トランスポート

### enrollment 完了通知（→ auto-gen-members.yaml 更新）

```hcl
# notifications/transports.tf
resource "authentik_notification_transport" "enrollment_webhook" {
  name = "enrollment-completed-webhook"
  mode = "webhook"

  webhook_url            = "https://api.github.com/repos/linuxclub/microservices-terraform/dispatches"
  webhook_mapping        = authentik_property_mapping_notification.enrollment_payload.pk
  send_once              = false
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
resource "authentik_notification_transport" "github_link_webhook" {
  name = "github-source-linked-webhook"
  mode = "webhook"

  webhook_url            = "https://api.github.com/repos/linuxclub/microservices-terraform/dispatches"
  webhook_mapping        = authentik_property_mapping_notification.github_link_payload.pk
  send_once              = false
}

resource "authentik_property_mapping_notification" "github_link_payload" {
  name       = "github-link-dispatch-payload"
  expression = <<-PYTHON
    event_type = notification.event.action  # source_linked or source_unlinked
    return {
      "event_type": f"authentik-{event_type}",
      "client_payload": {
        "username": notification.event.user.get("username", ""),
        "source":   notification.event.context.get("source", {}).get("slug", ""),
      }
    }
  PYTHON
}
```

---

## 通知ルール

```hcl
# notifications/rules.tf

# enrollment 完了 → auto-gen-members.yaml 更新 Webhook
resource "authentik_notification_rule" "enrollment_completed" {
  name              = "enrollment-completed"
  transports        = [authentik_notification_transport.enrollment_webhook.pk]
  severity          = "notice"
  group             = authentik_group.all_members.pk

  # model_created: authentik_core.user のみ対象
}

resource "authentik_event_matcher_policy" "enrollment_event" {
  name   = "match-enrollment-model-created"
  action = "model_created"
  model  = "authentik_core.user"
}

resource "authentik_policy_binding" "enrollment_rule_policy" {
  target = authentik_notification_rule.enrollment_completed.pk
  policy = authentik_event_matcher_policy.enrollment_event.pk
  order  = 0
}

# GitHub source_linked / source_unlinked → auto-gen-github-usernames.yaml 更新
resource "authentik_notification_rule" "github_source_change" {
  name       = "github-source-change"
  transports = [authentik_notification_transport.github_link_webhook.pk]
  severity   = "notice"
  group      = authentik_group.all_members.pk
}

resource "authentik_event_matcher_policy" "source_linked_event" {
  name   = "match-source-linked"
  action = "source_linked"
}

resource "authentik_event_matcher_policy" "source_unlinked_event" {
  name   = "match-source-unlinked"
  action = "source_unlinked"
}

resource "authentik_policy_binding" "source_linked_rule" {
  target = authentik_notification_rule.github_source_change.pk
  policy = authentik_event_matcher_policy.source_linked_event.pk
  order  = 0
}

resource "authentik_policy_binding" "source_unlinked_rule" {
  target = authentik_notification_rule.github_source_change.pk
  policy = authentik_event_matcher_policy.source_unlinked_event.pk
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
       └─ authentik_invitation "pending" が作成される（7日間有効）
            │
            └─ メンバーが招待リンクを受け取り、ブラウザで開く
                 │
                 ├─ ステージ 1: 招待コード検証
                 ├─ ステージ 2: username・display_name・パスワード入力
                 │   （username はここで本人が決める）
                 ├─ ステージ 3: ユーザー作成・all-members グループに追加
                 └─ ステージ 4: ログイン完了
                      │
                      └─ model_created イベント発火
                           └─ Webhook → GitHub Actions
                                └─ auto-gen-members.yaml に email:username を書き込み
                                     └─ 次回 terraform apply で module "user" が作成される
```

---

## 関連ドキュメント

- `03-member-management.md` — members_secrets.yaml.enc・auto-gen ファイルの詳細
- `10-roles-and-permissions.md` — ロール定義と権限マトリクス
