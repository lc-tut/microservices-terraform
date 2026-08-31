# メンバー管理・個人情報取り扱い

## 概要

サークルメンバーのアカウントは Authentik（IdP）で一元管理します。
Terraform はアカウントの**初期作成のみ**を担い、username・GitHub 連携は
メンバー自身が enrollment フローで設定します。

---

## 個人情報の分類と管理方針

| データ | 分類 | 管理方法 |
|--------|------|---------|
| id（内部 ID） | 非 PII | Git に平文でコミット OK |
| ロール | 非 PII | Git に平文でコミット OK |
| Student ID（C0A24XXXLL） | PII | SOPS（age）で暗号化して Git 管理 |
| Student Email | PII | SOPS（age）で暗号化して Git 管理 |
| username（自己選択） | 非 PII | Bot が `auto-gen-members.yaml` に自動記録 |
| display_name（自己設定） | 非 PII | Bot が `auto-gen-members.yaml` に自動記録 |
| GitHub username | 非 PII | Bot が `auto-gen-github-usernames.yaml` に自動記録 |
| パスワード・MFA シークレット | 機密 | Authentik が保持。Terraform では扱わない |

> Student Email は現在の大学メール形式（`c0a24XXXLL@edu.teu.ac.jp`）に学籍番号が含まれます。
> どちらか一方の漏洩が両方の漏洩に相当するため、同じ PII として扱います。
> **email は暗号化ファイル以外には一切出ません。**

---

## ファイル構成

```text
platform/members/
├── active/
│   ├── grad-2027/
│   │   ├── members.yaml              # 管理者: id・role（平文 OK）
│   │   ├── members_secrets.yaml.enc  # 管理者: email・student_id（SOPS 暗号化）
│   │   └── auto-gen-members.yaml     # Bot: username・display_name（enrollment 後）
│   └── grad-2026/
│       ├── members.yaml
│       ├── members_secrets.yaml.enc
│       └── auto-gen-members.yaml
├── ob-og/
│   └── grad-2025/
│       ├── members.yaml               # role: "ob-og"（平文のまま。id・role は特定情報ではない）
│       ├── members_secrets.yaml.enc
│       ├── auto-gen-members.yaml.enc      # 卒業後の匿名化により暗号化（下記参照）
│       ├── auto-gen-github-usernames.yaml.enc
│       └── auto-gen-discord-ids.yaml.enc
├── alumni/
│   └── grad-2024/
│       ├── members.yaml               # role: "alumni"（平文のまま）
│       ├── members_secrets.yaml.enc
│       ├── auto-gen-members.yaml.enc
│       ├── auto-gen-github-usernames.yaml.enc
│       └── auto-gen-discord-ids.yaml.enc
└── auto-gen-github-usernames.yaml    # Bot: username → github_username（OAuth 連携時。active のみ）
```

`ob-og` / `alumni` では `auto-gen-*.yaml` が `.enc` になり、`auto-gen-github-usernames.yaml` /
`auto-gen-discord-ids.yaml` もコホートフォルダ単位に分割されます（`active` のフラットファイルには
残りません）。これは `role` を無視するのではなく明示的に上書きする設計、および
「卒業後は `lcn_xxxxxx` 以外の本人特定情報を暗号化する」という匿名化方針の一部です。
詳細は [`documents/authentik/02-membership-lifecycle.md`](../authentik/02-membership-lifecycle.md)
の「卒業後の匿名化」を参照。

> `active` / `ob-og` / `alumni` の3層構成です。卒業後も部活動に関わり続ける
> OB/OG 向けの中間ステータスとして `ob-og/` を設けています。詳細は
> [`documents/authentik/02-membership-lifecycle.md`](../authentik/02-membership-lifecycle.md) 参照。

Bot ファイルは CODEOWNERS で Bot のみを承認者に指定し、人間のレビューなしで自動マージします。

```text
# .github/CODEOWNERS
terraform/platform/members/**/auto-gen-*.yaml    @github-actions[bot]
terraform/platform/members/auto-gen-*.yaml       @github-actions[bot]
```

---

## 各ファイルの内容

### members.yaml（管理者が管理・平文）

管理者が入会時に記入します。`id` は管理者が生成する安定した内部 ID です。
Terraform のリソースキーに使い、外部には公開しません。

`id` の形式は `lcn_` + UUID v4 先頭 12 文字（小文字 16 進数）です。

```bash
# id 生成コマンド
echo "lcn_$(uuidgen | tr -d '-' | cut -c1-12 | tr '[:upper:]' '[:lower:]')"
# → lcn_7f3a9b2c5e1d
```

```yaml
members:
  - id: "lcn_7f3a9b2c5e1d"
    role: "circle-admin"

  - id: "lcn_3e1d9f40ab2c"
    role: "member"
```

### members_secrets.yaml（管理者が管理・SOPS 暗号化）

キーは `id` です。email はこのファイルにのみ存在します。

```yaml
members:
  lcn_7f3a9b2c5e1d:
    email: "c0a24001aa@edu.teu.ac.jp"
    student_id: "C0A24001AA"
  lcn_3e1d9f40ab2c:
    email: "c0a24002bb@edu.teu.ac.jp"
    student_id: "C0A24002BB"
```

### auto-gen-members.yaml（Bot が自動更新・人間は編集しない）

enrollment flow 完了時に Bot が書き込みます。キーは `id` です。
email はここには入りません。

```yaml
# 自動生成 - 手動編集禁止
lcn_7f3a9b2c5e1d:
  username: "alice"
  display_name: "Alice"
# lcn_3e1d9f40ab2c はまだ enrollment 未完了 → エントリなし
```

### auto-gen-github-usernames.yaml（Bot が自動更新・人間は編集しない）

Authentik で GitHub OAuth 連携したタイミングで Bot が更新します。

```yaml
# 自動生成 - 手動編集禁止
lcn_7f3a9b2c5e1d: "alice-gh"
lcn_3e1d9f40ab2c: "bob-dev"
```

---

## Terraform での参照方法

> **注意（実装との乖離）**: 以下のコード例は当初の設計スケッチであり、
> 実際の `terraform/platform/members/authentik_users.tf` とは一致しません。
> 実装は `module "user"` ではなく `resource "authentik_user" "members"`
> （`for_each = local.members_by_id`）を直接使っており、`authentik_invitation`
> リソースも存在しません（Provider にそのリソース自体がありません。招待の実体は
> `authentik_stage_invitation` というステージ設定のみです）。実際の enrollment は
> 「`is_active = false` でユーザーを作成 → `null_resource` の `local-exec` から
> Authentik API を curl で叩いてリカバリーメールを送信する」という異なる仕組みです。
> また実コードは `email = local.secrets[each.key].email`（実メール）を直接渡しており、
> このドキュメント冒頭の「email は暗号化ファイル以外には一切出ません」という方針とも
> 食い違っています。この乖離自体は今回のセッションで作られたものではなく、
> 既存のコードとドキュメントの間に元々あったものです。`documents/authentik/` の
> 新しい設計（`lcn_id`・`grad_year` 属性の追加など）を実装する際は、
> このスケッチではなく実ファイル `terraform/platform/members/authentik_users.tf` を
> 起点に修正してください。

```hcl
locals {
  cohort_files = fileset("${path.module}/active", "*/members.yaml")

  # 管理者管理: id・role のリスト
  members_list = flatten([
    for f in local.cohort_files :
    yamldecode(file("${path.module}/active/${f}")).members
  ])

  # 管理者管理（暗号化）: id → {email, student_id}
  secrets = sensitive(merge([
    for f in local.cohort_files :
    yamldecode(file(
      "${path.module}/active/${dirname(f)}/members_secrets.yaml"
    )).members
  ]...))

  # Bot 自動生成: id → {username, display_name}
  auto_gen = merge([
    for f in fileset("${path.module}/active", "*/auto-gen-members.yaml") :
    yamldecode(file("${path.module}/active/${f}"))
  ]...)

  github_usernames = yamldecode(
    file("${path.module}/auto-gen-github-usernames.yaml")
  )
}

# enrollment 未完了のメンバーに招待リンクを発行
resource "authentik_invitation" "pending" {
  for_each = {
    for m in local.members_list : m.id => m
    if lookup(local.auto_gen, m.id, null) == null
  }

  name    = each.key
  expires = timeadd(timestamp(), "168h")
  flow    = data.authentik_flow.enrollment.slug

  fixed_data = {
    id    = each.key                          # Bot が webhook payload で受け取る
    email = "${each.key}@linuxclub.example"   # Mailu が real email に転送
  }
}

# enrollment 完了済みメンバーの Authentik ユーザーを管理
module "user" {
  for_each = {
    for m in local.members_list : m.id => m
    if lookup(local.auto_gen, m.id, null) != null
  }
  source = "../../../modules/authentik-user"

  username     = local.auto_gen[each.key].username
  display_name = local.auto_gen[each.key].display_name
  email        = "${each.key}@linuxclub.example"  # club alias のみ渡す
  student_id   = local.secrets[each.key].student_id

  lifecycle {
    # username は LC-Cloud Keystone ユーザー名と紐づくため削除を防ぐ
    prevent_destroy = true
  }
}

# GitHub Org メンバー管理（GitHub 連携済みのメンバーのみ）
resource "github_membership" "this" {
  for_each = {
    for m in local.members_list : m.id => m
    if(lookup(local.auto_gen, m.id, null) != null &&
      lookup(local.github_usernames, m.id, null) != null)
  }

  # github_usernames は id キー
  username = local.github_usernames[each.key]
  role     = each.value.role == "circle-admin" ? "admin" : "member"
}
```

---

## アカウント自動プロビジョニングフロー

> **注意（実装との乖離）**: 以下の図・コード例（「アカウント自動プロビジョニングフロー」
> 「Bot 自動更新フロー」「Mailu エイリアス同期」「メンバーライフサイクル」の「入会時」節）は
> 当初の設計スケッチで、実装とは複数の点で異なります（後続の「チームメンバーシップ」節以降は
> この乖離の対象外です）。
> - `scripts/sync-mail-aliases.sh` は存在しません。Mailu ではなく、
>   `members_secrets.yaml.enc` の `email` をそのまま Authentik User の email に
>   渡しています（`terraform/platform/members/authentik_users.tf`）
> - `.github/workflows/sync-members.yml` / `sync-github-usernames.yml` という
>   2つのワークフローではなく、`.github/workflows/authentik-dispatch.yml` 1つに
>   統合されています。`auto-gen-members.yaml` のキーも `id` ではなく `username`
>   （値は `{pk, display_name}`）です
> - 「GitHub OAuth連携（必須）」「WebAuthn MFA登録（必須）」は enrollment flow の
>   話ですが、招待制 Flow（`enrollment.tf`）自体を 2026-08-31 に削除しました
>   （実際に使われる経路ではなかったため）。実際の入会は `authentik_users.tf` が
>   直接ユーザーを作成し `member-recovery` Flow 経由の「ようこそ」メールで
>   パスワード・username を設定してもらう方式です（詳細は
>   `documents/authentik/02-membership-lifecycle.md`・`documents/authentik/forms/01-enrollment.md`・
>   `16-implementation-phases.md` の Phase 2 拡張節を参照）。
>   GitHub/Discord連携やMFA登録を必須にする仕組みは現状ありません
> - PR承認を経た手動 apply ではなく、Bot（`authentik-dispatch.yml`）が
>   `auto-gen-members.yaml` を直接コミット・プッシュします（`[skip ci]` 付き）

```text
管理者が members.yaml に id・role を追加
管理者が members_secrets.yaml に email・student_id を追加（SOPS 再暗号化）
  │
  └─ PR → 管理者承認 → apply
       │
       ├─ Authentik Invitation 作成
       │   fixed_data = { id: "lcn_xxx", email: "lcn_xxx@linuxclub.example" }
       │
       ├─ scripts/sync-mail-aliases.sh 実行
       │   └─ lcn_xxx@linuxclub.example → real email を Mailu に設定
       │
       └─ Authentik が招待メール送信（Mailu 経由で real email に届く）
            │
            └─ メンバーが招待リンクから enrollment flow を踏む
                 ├─ username 自己入力（LC-Cloud Keystone ID・以降変更不可）
                 ├─ display_name 設定
                 ├─ パスワード設定
                 ├─ GitHub OAuth 連携（必須）
                 └─ WebAuthn MFA 登録（必須）
                      │
                      ├─ Authentik webhook → GitHub Actions
                      │   → auto-gen-members.yaml に id をキーで書き込み
                      │   → 次の terraform apply で Authentik ユーザーが正式作成
                      │
                      └─ SCIM Outbound Provider
                          ├─ LC-Cloud API → Keystone ユーザー作成（username で）
                          ├─ OpenStack Project メンバー追加
                          └─ k8s Namespace の RoleBinding 自動設定
```

---

## Bot 自動更新フロー

### auto-gen-members.yaml（enrollment 完了時）

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

      - name: Update auto-gen-members.yaml
        run: |
          ID="${{ github.event.client_payload.id }}"
          USERNAME="${{ github.event.client_payload.username }}"
          DISPLAY_NAME="${{ github.event.client_payload.display_name }}"

          # id が属するコホートフォルダを特定
          COHORT_DIR=$(grep -rl "id: \"${ID}\"" \
            terraform/platform/members/active/*/members.yaml \
            | head -1 | xargs dirname)

          yq e ".\"${ID}\" = {\"username\": \"${USERNAME}\",
            \"display_name\": \"${DISPLAY_NAME}\"}" \
            -i "${COHORT_DIR}/auto-gen-members.yaml"

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add terraform/platform/members/active/**/auto-gen-members.yaml
          git commit -m "chore: record enrollment for \
            ${{ github.event.client_payload.username }}"
          git push
```

### auto-gen-github-usernames.yaml（GitHub OAuth 連携時）

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
            | jq -r '.results[0].attributes.github_username // empty')
          echo "username=${USERNAME}" >> $GITHUB_OUTPUT
          echo "github_username=${GITHUB_UN}" >> $GITHUB_OUTPUT

      - name: Resolve id from username
        id: resolve
        run: |
          USERNAME="${{ steps.fetch.outputs.username }}"
          ID=$(grep -rl "username: \"${USERNAME}\"" \
            terraform/platform/members/active/**/auto-gen-members.yaml \
            | xargs yq "to_entries[] | select(.value.username == \"${USERNAME}\") | .key" \
            | head -1)
          echo "id=${ID}" >> $GITHUB_OUTPUT

      - name: Update auto-gen-github-usernames.yaml
        run: |
          yq e '."${{ steps.resolve.outputs.id }}" =
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

## Mailu エイリアス同期

real email は `members_secrets.yaml.enc` にのみ存在します。
Mailu のエイリアス設定はスクリプトが直接 Mailu API を呼び出して行います。
State ファイルを生成しないため、real email が Terraform State に入りません。

```bash
# scripts/sync-mail-aliases.sh
# ローカル実行のみ。State ファイルを生成しない
for cohort in terraform/platform/members/active/*/; do
  sops -d "${cohort}members_secrets.yaml.enc" | \
    yq '.members | to_entries[]' | \
    while IFS= read -r entry; do
      id=$(echo "$entry" | yq '.key')
      real_email=$(echo "$entry" | yq '.value.email')
      curl -s -X POST "${MAILU_API}/alias" \
        -H "Authorization: Bearer ${MAILU_TOKEN}" \
        -d "{\"localpart\": \"${id}\",
             \"destination\": [\"${real_email}\"]}"
    done
done
```

---

## チームメンバーシップ

チームへの所属は `catalog/teams/<name>/members.yaml` で管理します。
enrollment 完了後（username が確定してから）チームリードが追加します。
1 人が複数チームに所属する場合はそれぞれのファイルに記載するだけです。

```yaml
# catalog/teams/infra/members.yaml
members:
  - alice
  - lcn_3e1d9f40ab2c
```

`username`（`alice`）と内部 ID（`lcn_3e1d9f40ab2c`）のどちらでも指定できます。
username バリデーションポリシー（`policy_username.tf`）がアンダースコアを許可していないため、
`lcn_` プレフィックス（アンダースコア込み）と衝突することはなく、`startswith(entry, "lcn_")` で
機械的に判別できます。

```hcl
locals {
  # id -> {username, display_name}（active コホートのみ。ob-og/alumni は
  # auto-gen-members.yaml.enc が暗号化されているため、この逆引きの対象外）
  username_to_id = {
    for id, info in local.auto_gen : info.username => id
  }

  team_member_ids = [
    for entry in yamldecode(file("${path.module}/members.yaml")).members :
    startswith(entry, "lcn_") ? entry : local.username_to_id[entry]
  ]
}
```

**`ob-og` / `alumni` になったメンバーを username で指定することはサポートしません。**
`documents/authentik/02-membership-lifecycle.md` の「卒業後の匿名化」により、
これらのメンバーの username は暗号化されて Terraform からは読めなくなるため、
`username_to_id` に該当キーが存在せず `terraform plan` がエラーで停止します
（意図的な仕様です。フォールバックで復号を試みたりはしません。該当メンバーを
チームに残す必要がある場合は `lcn_xxxxxx` で書き直してください）。

---

## メンバーライフサイクル

### 入会時

1. 管理者が `members.yaml` に `id`・`role` を追加
1. `members_secrets.yaml` に `email`・`student_id` を追加（SOPS で再暗号化）
1. PR → 管理者承認 → apply → Authentik Invitation 作成
1. `scripts/sync-mail-aliases.sh` を実行して Mailu エイリアスを設定
1. メンバーが招待メールから enrollment flow を完了（username・GitHub 連携）
1. Bot が `auto-gen-members.yaml` に自動記録 → 次の apply で Authentik ユーザー正式作成
1. enrollment 完了後、チームリードが `catalog/teams/<name>/members.yaml` に username を追加

### 卒業・退会時

卒業時の移行（`ob-og` へ残すか `alumni` へ移すか）と、卒業と無関係な毎年の継続確認は
[`documents/authentik/02-membership-lifecycle.md`](../authentik/02-membership-lifecycle.md)
で詳細設計しています。概要のみ:

1. 毎年3月、Google フォームで在籍中の全メンバーへ継続意思を確認
1. 回答をもとに管理者が `active/<年度>/` を `ob-og/<年度>/` または `alumni/<年度>/` へ
   フォルダごと移動（削除しない）
1. PR → 管理者承認 → apply
1. Authentik の `is_active` / グループ割り当てが移動先フォルダに応じて更新される

### ロール変更

1. `members.yaml` の `role` を変更
1. PR → 管理者承認 → apply

---

## SOPS 設定

```yaml
# .sops.yaml
creation_rules:
  - path_regex: .*_secrets\.yaml\.enc$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    # 管理者全員の公開鍵をカンマ区切りで列挙
```

```bash
# 暗号化（編集後に実行）
sops --encrypt members_secrets.yaml > members_secrets.yaml.enc

# 編集（復号→編集→再暗号化を自動で行う）
sops members_secrets.yaml.enc
```

---

## Terraform State への PII 混入防止

- Authentik に渡すメールは `{id}@linuxclub.example`（club alias）のみ → State に real email が入らない
- real email は `members_secrets.yaml.enc` にのみ存在し、Mailu 同期スクリプトが直接読む
- username・GitHub username は Authentik が保持し、Terraform State には入らない
- Student ID は Authentik ユーザー属性として State に含まれるため、
  State バックエンド（Ceph RGW）へのアクセスは管理者限定に制限する
