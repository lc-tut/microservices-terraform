# ロール・権限・CODEOWNERS

## 概要

リポジトリの変更権限は以下の3つの仕組みで強制します。

- **`.github/CODEOWNERS`**：Tier 1 は静的管理、Tier 2 は `terraform-provider-codeowners` で apply 時に自動更新
- **per-directory `.codeowners` + `codeowners-plus`**：Tier 3 の workspaces でフォルダごとに所有権を任意設定
- **GitHub Branch Protection**：PR 必須・CODEOWNERS レビュー強制

---

## ロール定義

| ロール | GitHub 上の表現 | 説明 |
|--------|---------------|------|
| **circle-admin** | `@org/circle-admin` | 役員（部長・副部長・幹部）。全 Tier 承認・組織最終決定権 |
| **tech-lead** | `@org/tech-lead` | 技術全般のリーダー。`platform/` 全体の技術的オーナー |
| **lc-cloud-infra** | `@org/lc-cloud-infra` | OpenStack・Ceph・K8s 担当。インフラ層・クォータ・IdP 管理 |
| **lc-cloud-platform** | `@org/lc-cloud-platform` | Terraform・Authentik・GitHub 担当。プラットフォーム・モジュール・CI/CD 管理 |
| **team-lead** | `@org/<team>-lead` | チームリード。自チームの catalog/ 承認・workspaces/ 自己完結 |
| **member** | GitHub Organization メンバー | PR を提出できる。承認権限は CODEOWNERS 次第 |
| **alumni** | GitHub Organization 外 | 退会済み。リポジトリへのアクセスなし |

### GitHub Teams 構成

```text
org/
├── circle-admin          # 役員グループ
├── tech-lead             # 技術リーダー
├── lc-cloud-infra        # インフラ担当
├── lc-cloud-platform     # プラットフォーム担当
├── all-leads             # 全チームリードの集合（Tier 3 デフォルト承認者）
├── infra-lead            # infra チームのリード（複数人推奨）
├── web-lead              # web チームのリード（複数人推奨）
└── （チームごとに追加）
```

> **注意**: team-lead は複数人を推奨します。GitHub の仕様上、PR 作成者は自分の CODEOWNERS 承認をカウントできないため、1人だと workspaces/ の自己完結が成立しません。

---

## 権限マトリクス

✅ = 承認・マージ可　[PR] = PR 提出可（上位ロールの承認が必要）　❌ = アクセス不可

| 操作 | circle-admin | tech-lead | lc-cloud-infra | lc-cloud-platform | team-lead | member |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| `platform/members/` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| `platform/idp/` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| `platform/quotas/` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| `platform/github/` | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| `modules/` | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| `catalog/billing-accounts/` | ✅ | ❌ | ✅ | ❌ | [PR] | [PR]（個人のみ） |
| `catalog/teams/` | ✅ | ❌ | ❌ | ✅ | ✅（自チーム）/ [PR] | [PR] |
| `catalog/projects/` | ✅ | ❌ | ❌ | ✅ | ✅（自プロジェクト）/ [PR] | [PR] |
| `workspaces/<name>/` | ✅ | ❌ | ❌ | ❌ | CODEOWNERS 次第 | CODEOWNERS 次第 |

> `workspaces/<name>/` は CODEOWNERS に含まれていれば ✅、含まれていなければ [PR] として CODEOWNERS オーナーの承認が必要です。

---

## CODEOWNERS 設計

承認権限の管理は Tier によって仕組みを使い分けます。

| Tier | 仕組み | 管理方法 |
|------|--------|---------|
| 🔴 Tier 1 | `.github/CODEOWNERS`（静的） | 手動・ほぼ変更なし |
| 🟡 Tier 2 | `.github/CODEOWNERS`（動的） | `terraform-provider-codeowners` が apply 時に自動更新 |
| 🟢 Tier 3 | per-directory `.codeowners` | team-lead が任意で配置、`codeowners-plus` が強制 |

参考リンク：

- [multimediallc/codeowners-plus](https://github.com/multimediallc/codeowners-plus)
- [form3tech-oss/terraform-provider-codeowners](https://github.com/form3tech-oss/terraform-provider-codeowners)

---

### `.github/CODEOWNERS`

Tier 1 は静的に管理します。Tier 2 は `terraform-provider-codeowners` が apply 時に自動生成するため手動編集不要です。
Tier 3 はワイルドカード1行のみ定義し、詳細は per-directory `.codeowners` に委ねます。

```text
# .github/CODEOWNERS
# Tier 2 は terraform apply で自動更新（手動編集不要）
# Tier 3 の詳細は各ディレクトリの .codeowners（codeowners-plus が強制）

# =============================================================
# 🔴 Tier 1：管理者のみ（静的）
# =============================================================
/terraform/platform/   @org/circle-admin
/terraform/modules/    @org/circle-admin

# =============================================================
# 🟡 Tier 2：以下は terraform apply により自動生成
# =============================================================
/terraform/catalog/billing-accounts/personal/                @org/circle-admin
/terraform/catalog/billing-accounts/personal/alice/          @org/circle-admin
/terraform/catalog/billing-accounts/teams/                   @org/circle-admin
/terraform/catalog/billing-accounts/teams/infra/             @org/circle-admin @org/infra-lead
/terraform/catalog/teams/                                    @org/circle-admin
/terraform/catalog/teams/infra/                              @org/circle-admin @org/infra-lead
/terraform/catalog/projects/                                 @org/circle-admin
/terraform/catalog/projects/my-product/                      @org/circle-admin @alice
/terraform/catalog/projects/team-app/                        @org/circle-admin @org/infra-lead
/terraform/catalog/projects/shared-app/                      @org/circle-admin @org/infra-lead @org/web-lead

# =============================================================
# 🟢 Tier 3：デフォルトは all-leads が承認
#            詳細は各ディレクトリの .codeowners で上書き可
# =============================================================
/terraform/workspaces/   @org/all-leads
```

### Tier 2 の自動管理（terraform-provider-codeowners）

`terraform/platform/github/codeowners.tf` で Tier 2 エントリを Terraform リソースとして管理します。
プロジェクトオーナーやチームリードの変更は `catalog/` の Terraform を更新して apply するだけで `.github/CODEOWNERS` に自動反映されます。

```hcl
# terraform/platform/github/codeowners.tf
resource "codeowners_file" "main" {
  repository = var.github_repo
  branch     = "main"

  dynamic "rules" {
    for_each = local.catalog_teams
    content {
      pattern = "/terraform/catalog/teams/${rules.key}/"
      owners  = ["@org/circle-admin", rules.value.lead]
    }
  }

  dynamic "rules" {
    for_each = local.catalog_projects
    content {
      pattern = "/terraform/catalog/projects/${rules.key}/"
      owners  = concat(["@org/circle-admin"], rules.value.owners)
    }
  }
}
```

### Tier 3 の per-directory `.codeowners`（codeowners-plus）

workspaces 配下で所有権を制限したいフォルダに team-lead が任意で `.codeowners` を配置します。
`.codeowners` がない場合は親ディレクトリへ再帰的にフォールバックし、最終的に `.github/CODEOWNERS` の `@org/all-leads` が適用されます。

```text
# terraform/workspaces/my-product/.codeowners（任意）
@org/circle-admin
@alice

# terraform/workspaces/shared-app/.codeowners（任意・複数チーム）
@org/circle-admin
@org/infra-lead
@org/web-lead
```

### `@org/circle-admin` 自動追加

workspaces の `.codeowners` に `@org/circle-admin` が含まれていない場合、GitHub Actions が PR へ自動でコミットして追加します。
管理者は常にすべてのフォルダを承認・変更できます。

```yaml
# .github/workflows/ensure-admin-codeowners.yml
name: Ensure Admin in .codeowners

on:
  pull_request:
    paths:
      - 'terraform/workspaces/**/.codeowners'

jobs:
  ensure-admin:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}
          token: ${{ secrets.BOT_TOKEN }}
      - run: |
          changed=false
          for f in $(git diff --name-only origin/${{ github.base_ref }} | grep '\.codeowners$'); do
            if ! grep -q '@org/circle-admin' "$f"; then
              sed -i '1i @org/circle-admin' "$f"
              changed=true
            fi
          done
          if [ "$changed" = "true" ]; then
            git config user.name "github-actions[bot]"
            git config user.email "github-actions[bot]@users.noreply.github.com"
            git add -A
            git commit -m "chore: add @org/circle-admin to .codeowners"
            git push
          fi
```

### CODEOWNERS の動作ルール

- **Tier 3 フォールバック**：`.codeowners` がないディレクトリは親を再帰的に遡り、最終的に `.github/CODEOWNERS` の `@org/all-leads` が適用される
- **PR 作成者は自分の承認をカウントできない**：個人オーナー（`@alice`）のプロジェクトは `@org/circle-admin` が代理承認
- **Tier 2 は手動編集禁止**：`terraform apply` で自動更新されるため `.github/CODEOWNERS` の Tier 2 部分を直接編集しない

---

## レビュー要件と通知

### Tier ごとのレビュー要件

| Tier | パス | 必要レビュー数 | 承認者（CODEOWNERS） | PR 提出者 |
|------|------|:---:|------|------|
| 🔴 Tier 1 | `platform/` `modules/` | **1** | `@org/circle-admin` | circle-admin のみ |
| 🟡 Tier 2 | `catalog/billing-accounts/` `catalog/teams/` `catalog/projects/` | **1** | admin + チームリードまたは本人 | 誰でも |
| 🟢 Tier 3 | `workspaces/` | **1** | チームリードまたは project-owner | チームメンバー・オーナー |

> レビュー数はすべて「1」で統一します。承認できる人物を CODEOWNERS で絞ることで、Tier ごとの実質的な権限分離を実現します。GitHub のネイティブ機能では「PR 作成者のロールに応じてレビュー数を変える」ことはできないため、この設計が最もシンプルです。

### 通知の仕組み

CODEOWNERS に登録されたユーザー・チームは、該当パスへの PR が開かれると GitHub が**自動的にレビュアーとしてアサイン**します。追加設定は不要です。

```text
PR 作成
  │
  ├─ GitHub が変更ファイルと CODEOWNERS をマッチング
  │
  ├─ 対象の GitHub Team / ユーザーへ自動レビュー依頼
  │   └─ チームメンバー全員に GitHub 通知（メール or Web）が届く
  │
  └─ Branch Protection により、承認なしのマージをブロック
```

### Discord 通知（オプション）

GitHub の通知に加えて Discord へ投稿したい場合、`sarisia/actions-status-discord` を使って GitHub Actions から Webhook 経由で送れます。
認証は Discord Webhook URL のみで、Bot token は不要です。

参考：[sarisia/actions-status-discord](https://github.com/sarisia/actions-status-discord)

```yaml
# .github/workflows/notify-discord.yml
name: Discord Review Notification

on:
  pull_request:
    types: [opened, ready_for_review]

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - name: Detect Tier
        id: tier
        run: |
          FILES=$(gh pr view ${{ github.event.pull_request.number }} --json files -q '.files[].path')
          if echo "$FILES" | grep -qE '^terraform/(platform|modules)/'; then
            echo "tier=🔴 Tier 1（管理者レビュー必須）" >> $GITHUB_OUTPUT
            echo "webhook=${{ secrets.DISCORD_WEBHOOK_ADMIN }}" >> $GITHUB_OUTPUT
          elif echo "$FILES" | grep -qE '^terraform/catalog/'; then
            echo "tier=🟡 Tier 2（管理者 or チームリードレビュー必須）" >> $GITHUB_OUTPUT
            echo "webhook=${{ secrets.DISCORD_WEBHOOK_LEADS }}" >> $GITHUB_OUTPUT
          else
            echo "tier=🟢 Tier 3（チームリードレビュー必須）" >> $GITHUB_OUTPUT
            echo "webhook=${{ secrets.DISCORD_WEBHOOK_TEAMS }}" >> $GITHUB_OUTPUT
          fi
        env:
          GH_TOKEN: ${{ github.token }}

      - name: Post to Discord
        uses: sarisia/actions-status-discord@v1
        with:
          webhook: ${{ steps.tier.outputs.webhook }}
          nodetail: true
          title: "${{ steps.tier.outputs.tier }} PR: ${{ github.event.pull_request.title }}"
          description: |
            **作成者:** ${{ github.event.pull_request.user.login }}
            ${{ github.event.pull_request.html_url }}
```

チャンネルを Tier で振り分けることで、管理者・各チームリードが自分に関係する通知だけを受け取れます。

### Tier 3 の自己承認問題と対策

GitHub の仕様上、PR 作成者は自分の CODEOWNERS 承認をカウントできません。

```text
例：alice が workspaces/my-product/ に PR を出した場合
  CODEOWNERS: @alice
  → alice 本人のレビューは無効
  → 別の承認者が存在しないとマージ不可
```

#### 対策

| 方法 | 内容 |
|------|------|
| team-lead を複数人にする | `@org/infra-lead` に 2 人以上登録することで互いに承認できる |
| project-owner に副オーナーを追加 | CODEOWNERS に `@alice @bob` と並記する |
| Tier 3 の自己承認を許可する | Branch Protection で circle-admin に bypass を付与し、オーナー本人が管理者に頼む運用（非推奨） |

---

> Branch Protection の詳細設定は `06-cicd.md` を参照してください。

---

## ロール付与フロー

### チームリードの追加

```text
1. terraform/platform/github/teams.tf の infra-lead チームにメンバーを追加して PR
2. 管理者が承認 → apply → GitHub Team に追加
3. .github/CODEOWNERS は自動的に有効（Team 名で参照しているため変更不要）
```

### プロジェクトオーナーの変更

```text
1. terraform/catalog/projects/<name>/variables.tf の owners を更新して PR
2. 管理者が承認 → terraform apply
   → terraform-provider-codeowners が .github/CODEOWNERS を自動更新
```

### メンバーの退会（alumni 化）

```text
1. terraform/platform/members/ で active → alumni に移動
2. GitHub Organization メンバーシップを削除
   → CODEOWNERS の個人エントリは無効化される（GitHub が Organization 外のユーザーを無視）
3. .github/CODEOWNERS から該当エントリを削除する PR を合わせて提出
```

---

## 新チーム・プロジェクト追加時の手順

新しいチームやプロジェクトは `catalog/` に Terraform を追加するだけです。
CODEOWNERS は apply 時に `terraform-provider-codeowners` が自動更新します。

```text
PR 内容：
  ├─ terraform/catalog/teams/new-team/authentik.tf   （チーム定義）
  ├─ terraform/catalog/teams/new-team/variables.tf   （owners など）
  └─ terraform/catalog/teams/new-team/outputs.tf

apply 後に自動更新：
  └─ .github/CODEOWNERS（手動編集不要）
       /terraform/catalog/teams/new-team/   @org/circle-admin @org/new-team-lead
```

`catalog/` への PR は `@org/circle-admin` の承認が必要なため、
チーム新規作成は必ず管理者の承認を通ります。
