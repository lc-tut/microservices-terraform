# メンバー管理・個人情報取り扱い

## 概要

サークルメンバーのアカウントは Authentik（IdP）で一元管理します。
Terraform は Authentik のユーザ・グループを管理し、アカウント作成から無効化までのライフサイクルを自動化します。

---

## 個人情報の分類と管理方針

| データ | 分類 | 管理方法 |
|--------|------|---------|
| username | 非 PII | ユーザーが enrollment 時に自己設定。`auto-gen-members.yaml` に Bot が自動記録。**変更不可** |
| display_name | 非 PII | ユーザーが enrollment 時に自己設定。`auto-gen-members.yaml` に Bot が自動記録 |
| ロール | 非 PII | 管理者が `members_secrets.yaml.enc` に設定 |
| github_username | 非 PII | `auto-gen-github-usernames.yaml` に自動書き込み（Authentik OAuth 連携時） |
| Student ID（C0A24XXXLL） | 準 PII | SOPS（age）で暗号化して Git 管理 |
| Student Email（`c0a24XXXLL@edu.teu.ac.jp`） | PII | SOPS（age）で暗号化して Git 管理 |
| パスワード・MFA シークレット | 機密 | Authentik が保持。Terraform では扱わない |

> username・display_name は管理者が決めるのではなく、ユーザー自身が enrollment flow で設定します。
> チーム所属は `catalog/teams/<name>/members.yaml` でチーム側から管理します（`05-project-lifecycle.md` 参照）。

---

## ファイル構成

卒業年度（コホート）ごとにフォルダを分けて管理します。
各コホートフォルダに管理者管理ファイルと Bot 自動生成ファイルの 2 種類を持ちます。

```text
platform/members/
├── active/
│   ├── grad-2027/
│   │   ├── members_secrets.yaml.enc  # 管理者: email・student_id・role（SOPS 暗号化）
│   │   └── auto-gen-members.yaml     # Bot: username・display_name（enrollment 後に自動記録）
│   └── grad-2026/
│       ├── members_secrets.yaml.enc
│       └── auto-gen-members.yaml
├── alumni/
│   └── grad-2025/
│       ├── members_secrets.yaml.enc
│       └── auto-gen-members.yaml
└── auto-gen-github-usernames.yaml    # Bot: GitHub username マップ（OAuth 連携時に自動更新）
```

### members_secrets.yaml（管理者が管理・SOPS で暗号化）

管理者が入会時に記入する唯一のファイルです。
email をキーとして扱い、username は持ちません（enrollment 後に確定するため）。

有効な `role` 値：`circle-admin` / `tech-lead` / `lc-cloud-infra` / `lc-cloud-platform` / `member`

```yaml
members:
  - email: "c0a24001aa@edu.teu.ac.jp"
    student_id: "C0A24001AA"
    role: "circle-admin"

  - email: "c0a24002bb@edu.teu.ac.jp"
    student_id: "C0A24002BB"
    role: "lc-cloud-infra"

  - email: "c0a24003cc@edu.teu.ac.jp"
    student_id: "C0A24003CC"
    role: "member"
```

### auto-gen-members.yaml（Bot が自動更新・人間は編集しない）

ユーザーが enrollment flow を完了した時点で GitHub Actions Bot が自動書き込みします。
email をキーに username・display_name を記録します。

```yaml
# 自動生成 - 手動編集禁止
"c0a24001aa@edu.teu.ac.jp":
  username: "alice"
  display_name: "Alice"
"c0a24002bb@edu.teu.ac.jp":
  username: "bob"
  display_name: "Bob"
# c0a24003cc はまだ enrollment 未完了 → エントリなし
```

### auto-gen-github-usernames.yaml（Bot が自動更新・人間は編集しない）

Authentik で GitHub OAuth 連携したタイミングで Bot が自動更新します。

```yaml
# 自動生成 - 手動編集禁止
alice: "alice42"
bob: "bob-dev"
```

Bot ファイルは CODEOWNERS で Bot のみを承認者に指定し、人間のレビューなしで自動マージします。

```text
# .github/CODEOWNERS
terraform/platform/members/**/auto-gen-*.yaml  @github-actions[bot]
```

---

## Terraform での参照方法

`members_secrets.yaml.enc` と `auto-gen-members.yaml` を email をキーに結合します。
`auto-gen-members.yaml` にエントリがないメンバーは enrollment 未完了として招待リソースを作成します。

```hcl
locals {
  secret_files = fileset("${path.module}/active", "*/members_secrets.yaml")
  autogen_files = fileset("${path.module}/active", "*/auto-gen-members.yaml")

  # 管理者管理: email・student_id・role のリスト
  secrets_list = sensitive(flatten([
    for f in local.secret_files :
    yamldecode(sops_decrypt_file("${path.module}/active/${f}")).members
  ]))

  # Bot 自動生成: email → {username, display_name} のマップ
  auto_gen = merge([
    for f in local.autogen_files :
    yamldecode(file("${path.module}/active/${f}"))
  ]...)

  github_usernames = yamldecode(file("${path.module}/auto-gen-github-usernames.yaml"))

  # enrollment 完了済みのみ（auto_gen に email がある）
  enrolled = [
    for m in local.secrets_list :
    merge(m, local.auto_gen[m.email])
    if lookup(local.auto_gen, m.email, null) != null
  ]
}

# enrollment 未完了のメンバーに招待リンクを発行
resource "authentik_invitation" "pending" {
  for_each = {
    for m in local.secrets_list : m.email => m
    if lookup(local.auto_gen, m.email, null) == null
  }

  name       = each.key
  expires    = timeadd(timestamp(), "168h")  # 7日間有効
  flow       = data.authentik_flow.enrollment.slug
  fixed_data = { email = each.value.email }
}

# enrollment 完了済みメンバーの Authentik ユーザーを管理
module "user" {
  for_each = { for m in local.enrolled : m.username => m }
  source   = "../../../modules/authentik-user"

  username     = each.value.username
  display_name = each.value.display_name
  email        = each.value.email
  student_id   = each.value.student_id

  lifecycle {
    # username は LC-Cloud Keystone ユーザー名と紐づくため削除を防ぐ
    prevent_destroy = true
  }
}

# GitHub Org メンバー管理（github_username が設定されている人のみ）
resource "github_membership" "this" {
  for_each = {
    for m in local.enrolled : m.username => m
    if lookup(local.github_usernames, m.username, null) != null
  }

  username = local.github_usernames[each.key]
  role     = each.value.role == "circle-admin" ? "admin" : "member"
}
```

---

## GitHub 連携

GitHub 連携は任意です。連携するとチームの GitHub Org メンバーになり CODEOWNERS のレビュワーになれます。
連携しなくてもサークルの Authentik・LC-Cloud 利用には影響しません。

```text
連携あり → GitHub Org メンバー → CODEOWNERS で個人指定可能
連携なし → GitHub Org に入らない → CODEOWNERS は @org/all-leads にフォールバック
```

### Authentik GitHub OAuth Source

Authentik に GitHub OAuth Source を設定します（任意連携）。
メンバーがログイン後のプロフィール画面から任意で GitHub アカウントを紐づけます。

```hcl
# terraform/platform/idp/providers/github_source.tf
resource "authentik_source_oauth" "github" {
  name                = "GitHub"
  slug                = "github"
  provider_type       = "github"
  consumer_key        = var.github_oauth_client_id
  consumer_secret     = var.github_oauth_client_secret
  # ログイン用ではなく「アカウント連携」用として設定
  authentication_flow = null
  enrollment_flow     = null
}
```

### auto-gen-github-usernames.yaml の自動更新フロー

Authentik の `source_linked` / `source_unlinked` イベントをトリガーに
GitHub Actions が `auto-gen-github-usernames.yaml` を自動更新・自動マージします。

```text
メンバーが Authentik で GitHub アカウントを連携（または変更）
  │
  └─ Authentik が source_linked イベントを発火
       └─ Webhook → GitHub Actions (repository_dispatch)
            │
            ├─ Authentik API で github_username を取得
            │   GET /api/v3/core/users/?username={username}
            │   → attributes.github_username
            │
            ├─ auto-gen-github-usernames.yaml を更新
            │   alice: "alice42"
            │
            └─ Bot が直接 main にコミット（CODEOWNERS で承認者 = bot）
                 │
                 └─ 次の terraform apply で GitHub Org メンバーシップに反映
```

アカウントを変更した場合（`source_unlinked` → `source_linked`）も同じフローで
`auto-gen-github-usernames.yaml` が上書きされます。

> 変更時点で open になっている PR のレビュー依頼は旧アカウント宛のままになります。
> 次回 terraform apply 後は CODEOWNERS が更新されるため、以降の PR は新アカウント宛になります。

### GitHub Actions ワークフロー

```yaml
# .github/workflows/sync-github-usernames.yml
on:
  repository_dispatch:
    types: [authentik-source-linked, authentik-source-unlinked]

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Fetch github_username from Authentik
        id: fetch
        run: |
          USERNAME="${{ github.event.client_payload.username }}"
          GITHUB_UN=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.AUTHENTIK_TOKEN }}" \
            "${AUTHENTIK_URL}/api/v3/core/users/?username=${USERNAME}" \
            | jq -r '.results[0].attributes.github_username // "null"')
          echo "username=${USERNAME}" >> $GITHUB_OUTPUT
          echo "github_username=${GITHUB_UN}" >> $GITHUB_OUTPUT

      - name: Update auto-gen-github-usernames.yaml
        run: |
          yq e '.${{ steps.fetch.outputs.username }} =
            "${{ steps.fetch.outputs.github_username }}"' \
            -i terraform/platform/members/auto-gen-github-usernames.yaml

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add terraform/platform/members/auto-gen-github-usernames.yaml
          git commit -m "chore: sync github_username for \
            ${{ steps.fetch.outputs.username }}"
          git push
```

---

## アカウント自動プロビジョニングフロー

```text
管理者が members_secrets.yaml.enc に email・student_id・role を追加
  │
  └─ PR → 管理者承認 → apply
       │
       └─ Authentik Invitation リソース作成 → 招待メール送信
            │
            └─ ユーザーが招待リンクから enrollment flow を踏む
                 ├─ username を自己入力（LC-Cloud Keystone ID になる・変更不可）
                 ├─ display_name を入力
                 ├─ パスワード設定
                 └─ WebAuthn MFA 登録
                      │
                      ├─ Authentik webhook → GitHub Actions
                      │   → auto-gen-members.yaml に username・display_name を書き込み
                      │   → 次の terraform apply で Authentik ユーザーが正式作成
                      │
                      └─ SCIM Outbound Provider
                          ├─ LC-Cloud API → Keystone ユーザー作成
                          ├─ OpenStack Project メンバー追加
                          └─ k8s Namespace の RoleBinding 自動設定
```

### auto-gen-members.yaml の自動更新フロー

Authentik の enrollment flow 完了イベントをトリガーに Bot が `auto-gen-members.yaml` を更新します。

```yaml
# .github/workflows/sync-members.yml
on:
  repository_dispatch:
    types: [authentik-enrollment-completed]

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Fetch user info from Authentik
        id: fetch
        run: |
          EMAIL="${{ github.event.client_payload.email }}"
          USER=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.AUTHENTIK_TOKEN }}" \
            "${AUTHENTIK_URL}/api/v3/core/users/?email=${EMAIL}" \
            | jq -r '.results[0]')
          echo "email=${EMAIL}" >> $GITHUB_OUTPUT
          echo "username=$(echo $USER | jq -r '.username')" >> $GITHUB_OUTPUT
          echo "display_name=$(echo $USER | jq -r '.name')" >> $GITHUB_OUTPUT

      - name: Update auto-gen-members.yaml
        run: |
          # コホートフォルダを特定してファイルを更新
          COHORT_DIR=$(grep -rl "${{ steps.fetch.outputs.email }}" \
            terraform/platform/members/active/*/members_secrets.yaml \
            | head -1 | xargs dirname)
          yq e '."${{ steps.fetch.outputs.email }}" = {
            "username": "${{ steps.fetch.outputs.username }}",
            "display_name": "${{ steps.fetch.outputs.display_name }}"
          }' -i "${COHORT_DIR}/auto-gen-members.yaml"

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add terraform/platform/members/active/**/auto-gen-members.yaml
          git commit -m "chore: record enrollment for ${{ steps.fetch.outputs.username }}"
          git push
```

---

## メンバーライフサイクル

### 入会時

1. 管理者が `members_secrets.yaml.enc` に email・student_id・role を追加（SOPS で再暗号化）
2. PR → 管理者承認 → apply → Authentik Invitation が作成される
3. メンバーに招待メールが届く
4. メンバーが enrollment flow で username・display_name・パスワード・MFA を設定
5. Authentik webhook → `auto-gen-members.yaml` に自動書き込み（Bot が commit）
6. 次の apply で Authentik ユーザーが正式作成 → SCIM で LC-Cloud に同期

### 卒業・退会時

1. `active/<年度>/` から `alumni/<年度>/` へフォルダごと移動（削除しない）
2. PR → 管理者承認 → apply
3. Authentik の `is_active = false` に変更、SCIM 連携で LC-Cloud アクセスも自動無効化

### ロール変更

1. `members_secrets.yaml.enc` の `role` を変更（SOPS で再暗号化）
2. PR → 管理者承認 → apply

---

## 年度末確認フロー

年度末に cron が卒業予定メンバーを検出し、**Authentik の Notification** で管理者グループに通知します。
管理者が確認のうえ PR を作成することで、システムには変更の事実のみが記録されます。

```text
3月初旬 cron（LC-Cloud cronjob または GitHub Actions）
  │
  └─ `active/grad-<今年>/` フォルダの存在を確認
       │
       └─ Authentik API: カスタムイベントを送信
            │
            └─ Authentik Notification Rule が発火
                 └─ Transport（メール / Slack）で管理者グループに通知
                      「grad-<今年> コホートの卒業確認をしてください」
                           │
              ┌────────────┴─────────────┐
              │                          │
         継続者あり                  全員卒業
              │                          │
         対応不要                    管理者が PR を作成
         （grad-<今年> フォルダに    （active/grad-<今年>/ を
           そのまま残す）              alumni/grad-<今年>/ に移動）
              │                          │
              └──────────┬───────────────┘
                         │
              継続者あり：翌年度末に再確認
              全員卒業：管理者が承認 → apply
```

> **将来の拡張（TBD）**: Authentik 上で管理者が承認操作を行った時点で
> Webhook 経由で PR を自動生成する仕組みを検討中。
> 現在は通知を受けた管理者が手動で PR を作成する運用とする。

### Authentik 側の設定

#### Notification Transport

Discord への通知経路を Terraform で定義します。
Authentik にネイティブの Discord 対応はありませんが、`webhook_slack` モードに
Discord Webhook URL の末尾へ `/slack` を付加することで動作します
（Discord が Slack 互換フォーマットを受け付けるため）。

```hcl
# terraform/platform/idp/providers/notification.tf
resource "authentik_event_transport" "discord" {
  name        = "graduation-review-discord"
  mode        = "webhook_slack"
  send_once   = false
  webhook_url = "${var.discord_webhook_url}/slack"
}
```

#### Notification Rule

管理者グループへのルールを設定します。

```hcl
resource "authentik_notification_rule" "graduation" {
  name       = "graduation-review"
  group      = data.authentik_group.circle_admin.id
  transports = [authentik_event_transport.discord.id]
  severity   = "notice"

  # カスタムイベント "graduation_review" にマッチ
  conditions = jsonencode({
    event_action = "custom_graduation_review"
  })
}
```

#### cron からの通知トリガー

```bash
#!/bin/bash
# 毎年 3月1日に実行する軽量スクリプト
YEAR=$(date +%Y)
FOLDER="terraform/platform/members/active/grad-${YEAR}"

if [ -d "$FOLDER" ]; then
  # Authentik API にカスタムイベントを送信
  curl -s -X POST "${AUTHENTIK_URL}/api/v3/events/notifications/" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"action\": \"custom_graduation_review\",
      \"context\": {
        \"cohort\": \"grad-${YEAR}\",
        \"message\": \"grad-${YEAR} コホートの卒業確認をしてください\"
      }
    }"
fi
```

---

## SOPS 設定

```yaml
# .sops.yaml
creation_rules:
  - path_regex: .*_secrets\.yaml\.enc$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    # 管理者全員の公開鍵をカンマ区切りで列挙
```

### 暗号化・復号コマンド

```bash
# 暗号化（編集後に実行）
sops --encrypt members_secrets.yaml > members_secrets.yaml.enc

# 復号（確認時）
sops --decrypt members_secrets.yaml.enc

# 編集（復号→編集→再暗号化を自動で行う）
sops members_secrets.yaml.enc
```

---

## Terraform State への PII 混入防止

- `sensitive = true` をすべての PII 変数・出力に付与
- Authentik の `authentik_user` リソースは email を State に保存するため、**State を PII フリーにはできない**
- そのため State バックエンド（Ceph RGW）へのアクセスは管理者のみに制限する
- State ファイルの暗号化は Ceph 側で対応済みのため、OpenTofu の State 暗号化機能は使用しない
