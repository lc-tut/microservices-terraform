# ワークスペース設定（project-config.yaml）

## 概要

`project-config.yaml` は各ワークスペースディレクトリに任意で配置できる設定ファイルです。
GitHub Actions が PR トリガー時・マージ時に読み取り、CI/CD の動作を制御します。

---

## 配置場所

```text
terraform/workspaces/
├── teams/
│   └── infra/
│       └── project-config.yaml   # チームワークスペースの設定
└── projects/
    └── my-product/
        └── project-config.yaml   # プロジェクトワークスペースの設定
```

---

## フィールドリファレンス

```yaml
# terraform/workspaces/my-product/project-config.yaml

# --- レビュー ---
# 必要承認数。0 = 承認なしでオーナー本人がマージ可。
# デフォルト: 0
required_reviews: 0

# 新コミットが push されたとき既存の承認を無効化するか。
# デフォルト: false
dismiss_stale_reviews: false

# --- Apply ---
# マージ後に自動で terraform apply を実行するか。
# false の場合は GitHub Environment の手動承認ゲートを経由。
# デフォルト: true
auto_apply: true

# --- 通知 ---
# PR 通知先の Discord Webhook URL を上書きする。
# 省略時はリポジトリ全体のデフォルト（DISCORD_WEBHOOK_TEAMS）を使用。
discord_webhook: ""

# --- セキュリティ ---
# tfsec / checkov によるセキュリティスキャンを実行するか。
# デフォルト: true
security_scan: true

# --- メタ ---
# 人間が読む説明。CI の動作には影響しない。
description: ""
```

---

## フィールド詳細

### `required_reviews`

| 値 | 動作 |
|----|------|
| `0`（デフォルト） | 承認不要。オーナー本人が即マージ可 |
| `1` | CODEOWNERS に登録されたオーナー以外の1人が承認する必要あり |
| `2` 以上 | 複数人の承認が必要 |

> GitHub の仕様上、PR 作成者は自分の承認をカウントできません。
> `required_reviews: 1` 以上にした場合、オーナー本人は自己マージ不可になります。

### `auto_apply`

| 値 | 動作 |
|----|------|
| `true`（デフォルト） | main マージ後に自動で `terraform apply` |
| `false` | GitHub Environment の手動承認ゲートを経由してから apply |

本番相当のリソースを管理するワークスペースでは `false` を推奨します。

### `discord_webhook`

省略時はリポジトリ Secrets の `DISCORD_WEBHOOK_TEAMS` が使われます。
プロジェクト専用チャンネルに通知したい場合のみ設定します。

値は Secrets に保管し、ここには Secret 名を参照する形で記載することを推奨します。

### `security_scan`

`false` にすると tfsec・checkov をスキップします。
学習・実験用など、スキャン失敗を無視したい場合のみ使います。

---

## デフォルト値まとめ

`project-config.yaml` が存在しない場合、またはフィールドが省略された場合の動作です。

| フィールド | デフォルト |
|-----------|-----------|
| `required_reviews` | `0` |
| `dismiss_stale_reviews` | `false` |
| `auto_apply` | `true` |
| `discord_webhook` | `DISCORD_WEBHOOK_TEAMS` Secret を使用 |
| `security_scan` | `true` |
| `description` | （空） |

---

## CI での読み取り方法

GitHub Actions の plan / apply ワークフローが各スタックの設定を読み取ります。

```yaml
# .github/workflows/plan.yml（抜粋）
- name: Load project config
  id: config
  working-directory: ${{ matrix.stack }}
  run: |
    if [ -f project-config.yaml ]; then
      required_reviews=$(yq '.required_reviews // 0' project-config.yaml)
      auto_apply=$(yq '.auto_apply // true' project-config.yaml)
      security_scan=$(yq '.security_scan // true' project-config.yaml)
      discord_webhook=$(yq '.discord_webhook // ""' project-config.yaml)
    else
      required_reviews=0
      auto_apply=true
      security_scan=true
      discord_webhook=""
    fi
    echo "required_reviews=$required_reviews" >> $GITHUB_OUTPUT
    echo "auto_apply=$auto_apply" >> $GITHUB_OUTPUT
    echo "security_scan=$security_scan" >> $GITHUB_OUTPUT
    echo "discord_webhook=${discord_webhook:-${{ secrets.DISCORD_WEBHOOK_TEAMS }}}" >> $GITHUB_OUTPUT

- name: Check review count
  if: steps.config.outputs.required_reviews != '0'
  run: |
    approvals=$(gh pr view ${{ github.event.pull_request.number }} \
      --json reviews -q '[.reviews[] | select(.state=="APPROVED")] | length')
    required=${{ steps.config.outputs.required_reviews }}
    if [ "$approvals" -lt "$required" ]; then
      echo "承認が不足しています（$approvals / $required）"
      exit 1
    fi
  env:
    GH_TOKEN: ${{ github.token }}
```

---

## 設定例

### 個人プロジェクト（自己マージ可）

```yaml
# terraform/workspaces/alice-sandbox/project-config.yaml
required_reviews: 0
auto_apply: true
description: "Alice の実験用ワークスペース"
```

### チームプロジェクト（レビュー必須・本番）

```yaml
# terraform/workspaces/team-app/project-config.yaml
required_reviews: 1
dismiss_stale_reviews: true
auto_apply: false
discord_webhook: ""   # DISCORD_WEBHOOK_TEAMS を使用
security_scan: true
description: "infra チームの本番プロジェクト"
```

### チームワークスペース（専用チャンネルに通知）

```yaml
# terraform/workspaces/infra-shared/project-config.yaml
required_reviews: 1
auto_apply: true
discord_webhook: "https://discord.com/api/webhooks/xxx/yyy"
description: "infra チームの共有ワークスペース"
```
