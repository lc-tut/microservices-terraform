# CI/CD 設計

## 概要

GitHub Actions を使い、すべての Terraform 操作を PR ベースで自動化します。
直接の `terraform apply` は禁止し、必ず CI を通じた変更のみを本番に反映します。

---

## フロー全体像

```text
開発者が PR を作成
  │
  ├─ [自動] 変更フォルダの検出
  ├─ [自動] terraform validate / fmt チェック
  ├─ [自動] tfsec / Checkov セキュリティスキャン
  ├─ [自動] terraform plan 実行
  ├─ [自動] plan 結果を PR コメントに投稿
  │
  ├─ [手動] CODEOWNERS による承認
  │
  └─ main にマージ
      │
      └─ [自動] terraform apply（フェーズ順に実行）
            Phase 1: platform/
            Phase 2: catalog/billing-accounts/   ← Phase 1 完了後
            Phase 3: catalog/teams|projects/ + platform/github   ← Phase 2 完了後
            Phase 4: workspaces/   ← Phase 3 完了後
```

apply はスタック間の依存関係に従ってフェーズ順に実行します。
各フェーズ内は並列実行ですが、同一スタックへの同時 apply は `concurrency` でキューイングします。

---

## GitHub Actions ワークフロー

> **注意（実装との乖離）**: 以下の `plan.yml`・`apply.yml`・`modules-check.yml`・
> `codeowners-check.yml` のコード例は、全体の設計思想（フェーズ順 apply・PR ベース・
> CODEOWNERS 承認ゲート）は実装と一致していますが、細部は実ファイルと異なります。
> - `terraform_version: "~1.9"` → 実際は `"~1.10"`
> - 各ワークフローに `メンバーファイル復号`（`scripts/decrypt-members.sh` を実行）
>   ステップが `SOPS復号キー設定` の直後に追加されている（`terraform/platform/members/`
>   の `*.yaml.enc` を復号してから plan/apply する必要があるため）
> - セキュリティスキャンは `tfsec . && checkov -d .` を validate ステップ内で
>   直接実行するのではなく、`aquasecurity/tfsec-action@v1.0.3`（`soft_fail: true`）を
>   別ステップとして使う方式に変更（`checkov` は使っていない）
> - Plan/Apply ステップの `env` に `GITHUB_TOKEN: ${{ secrets.GH_TERRAFORM_TOKEN }}`
>   が追加されている（`terraform/platform/github/` の GitHub provider 用）
> - `codeowners-check.yml` は `fetch-depth: 0` を指定せず、
>   `multimediallc/codeowners-plus@v1` には `base_ref` ではなく
>   `token: ${{ github.token }}` を渡している
>
> また、このドキュメント作成後に以下の2ワークフローが追加されています
> （詳細は下の「その他のワークフロー」節参照）。
> - `.github/workflows/authentik-dispatch.yml` — Authentik からの
>   `repository_dispatch` を受けて `auto-gen-members.yaml` 等を自動更新
>   （`03-member-management.md` 参照）
> - `.github/workflows/ensure-admin-codeowners.yml` — `terraform/workspaces/**/.codeowners`
>   の変更 PR に `@lc-tut/circle-admin` が含まれていなければ自動で先頭に追記してコミット

### plan ワークフロー（PR トリガー）

```yaml
# .github/workflows/plan.yml
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'terraform/platform/**'
      - 'terraform/catalog/**'
      - 'terraform/workspaces/**'
      - 'terraform/modules/**'

permissions:
  contents: read
  pull-requests: write

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      stacks: ${{ steps.detect.outputs.stacks }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: detect
        run: |
          # 変更があったルートモジュール（backend.tf を持つフォルダ）を検出
          stacks=$(git diff --name-only origin/main \
            | grep -E '^terraform/(platform|catalog|workspaces)/' \
            | awk -F'/' '$2=="platform"{print $1"/"$2"/"$3} $2!="platform"{print $1"/"$2"/"$3"/"$4}' \
            | sort -u \
            | jq -R -s -c 'split("\n")[:-1]')
          echo "stacks=$stacks" >> $GITHUB_OUTPUT

  plan:
    needs: detect-changes
    if: needs.detect-changes.outputs.stacks != '[]'
    strategy:
      matrix:
        stack: ${{ fromJson(needs.detect-changes.outputs.stacks) }}
      fail-fast: false
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # 認証情報は GitHub Secrets から取得
      # AUTHENTIK_TOKEN, LC_CLOUD_APP_CRED_ID, LC_CLOUD_APP_CRED_SECRET を設定しておく

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"

      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt

      - name: Validate & Security Scan
        working-directory: ${{ matrix.stack }}
        run: |
          terraform init -backend=false
          terraform validate
          terraform fmt -check
          tfsec . --no-color
          checkov -d . --quiet

      - name: Plan
        id: plan
        working-directory: ${{ matrix.stack }}
        env:
          TF_VAR_authentik_token: ${{ secrets.AUTHENTIK_TOKEN }}
          OS_APPLICATION_CREDENTIAL_ID: ${{ secrets.LC_CLOUD_APP_CRED_ID }}
          OS_APPLICATION_CREDENTIAL_SECRET: ${{ secrets.LC_CLOUD_APP_CRED_SECRET }}
          # S3 バックエンド（Ceph RGW）認証情報
          AWS_ENDPOINT_URL_S3: ${{ secrets.CEPH_RGW_ENDPOINT }}
          AWS_ACCESS_KEY_ID: ${{ secrets.CEPH_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.CEPH_SECRET_ACCESS_KEY }}
        run: |
          terraform init
          terraform plan -no-color -out=tfplan 2>&1 | tee plan.txt
        continue-on-error: true

      - name: PR コメントに結果を投稿
        uses: actions/github-script@v7
        env:
          PLAN: ${{ steps.plan.outputs.stdout }}
        with:
          script: |
            const fs = require('fs')
            const plan = fs.readFileSync('${{ matrix.stack }}/plan.txt', 'utf8')
            const status = '${{ steps.plan.outcome }}' === 'success' ? '✅' : '❌'
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### ${status} Plan: \`${{ matrix.stack }}\`\n\`\`\`\n${plan.slice(-60000)}\n\`\`\``
            })

      - name: Plan 失敗時に CI を失敗させる
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

### apply ワークフロー（main マージトリガー）

スタック間の依存関係に従い 4 フェーズで実行します。
`catalog/` に変更がある場合は `platform/github`（CODEOWNERS 自動更新）を Phase 3 に自動追加します。

```yaml
# .github/workflows/apply.yml
name: Terraform Apply

on:
  push:
    branches: [main]
    paths:
      - 'terraform/platform/**'
      - 'terraform/catalog/**'
      - 'terraform/workspaces/**'

permissions:
  contents: read

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      phase1: ${{ steps.detect.outputs.phase1 }}
      phase2: ${{ steps.detect.outputs.phase2 }}
      phase3: ${{ steps.detect.outputs.phase3 }}
      phase4: ${{ steps.detect.outputs.phase4 }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - id: detect
        run: |
          changed=$(git diff --name-only HEAD~1 HEAD)

          # Phase 1: platform/（3 階層）
          phase1=$(echo "$changed" \
            | grep -E '^terraform/platform/' \
            | awk -F'/' '{print $1"/"$2"/"$3}' \
            | sort -u \
            | jq -R -s -c 'split("\n")[:-1]')

          # Phase 2: catalog/billing-accounts/（5 階層: catalog/billing-accounts/<type>/<name>/）
          phase2=$(echo "$changed" \
            | grep -E '^terraform/catalog/billing-accounts/' \
            | awk -F'/' '{print $1"/"$2"/"$3"/"$4"/"$5}' \
            | sort -u \
            | jq -R -s -c 'split("\n")[:-1]')

          # Phase 3: catalog/teams|projects/ + platform/github（CODEOWNERS 自動更新）
          phase3_raw=$(echo "$changed" \
            | grep -E '^terraform/catalog/(teams|projects)/' \
            | awk -F'/' '{print $1"/"$2"/"$3"/"$4}' \
            | sort -u)
          if echo "$changed" | grep -qE '^terraform/catalog/'; then
            phase3_raw=$(printf '%s\nterraform/platform/github' "$phase3_raw")
          fi
          phase3=$(echo "$phase3_raw" | grep -v '^$' | sort -u \
            | jq -R -s -c 'split("\n")[:-1]')

          # Phase 4: workspaces/（4 階層）
          phase4=$(echo "$changed" \
            | grep -E '^terraform/workspaces/' \
            | awk -F'/' '{print $1"/"$2"/"$3"/"$4}' \
            | sort -u \
            | jq -R -s -c 'split("\n")[:-1]')

          echo "phase1=$phase1" >> $GITHUB_OUTPUT
          echo "phase2=$phase2" >> $GITHUB_OUTPUT
          echo "phase3=$phase3" >> $GITHUB_OUTPUT
          echo "phase4=$phase4" >> $GITHUB_OUTPUT

  apply-phase1:
    needs: detect-changes
    if: needs.detect-changes.outputs.phase1 != '[]'
    strategy:
      matrix:
        stack: ${{ fromJson(needs.detect-changes.outputs.phase1) }}
      fail-fast: false
    concurrency:
      group: apply-${{ matrix.stack }}
      cancel-in-progress: false
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      # 認証情報は GitHub Secrets から取得
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Apply
        working-directory: ${{ matrix.stack }}
        env:
          TF_VAR_authentik_token: ${{ secrets.AUTHENTIK_TOKEN }}
          OS_APPLICATION_CREDENTIAL_ID: ${{ secrets.LC_CLOUD_APP_CRED_ID }}
          OS_APPLICATION_CREDENTIAL_SECRET: ${{ secrets.LC_CLOUD_APP_CRED_SECRET }}
          AWS_ENDPOINT_URL_S3: ${{ secrets.CEPH_RGW_ENDPOINT }}
          AWS_ACCESS_KEY_ID: ${{ secrets.CEPH_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.CEPH_SECRET_ACCESS_KEY }}
        run: |
          terraform init
          terraform apply -auto-approve

  apply-phase2:
    needs: [detect-changes, apply-phase1]
    if: |
      always() &&
      (needs.apply-phase1.result == 'success' || needs.apply-phase1.result == 'skipped') &&
      needs.detect-changes.outputs.phase2 != '[]'
    strategy:
      matrix:
        stack: ${{ fromJson(needs.detect-changes.outputs.phase2) }}
      fail-fast: false
    concurrency:
      group: apply-${{ matrix.stack }}
      cancel-in-progress: false
    runs-on: ubuntu-latest
    environment: production
    steps: # apply-phase1 と同一
      - uses: actions/checkout@v4
      # 認証情報は GitHub Secrets から取得
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Apply
        working-directory: ${{ matrix.stack }}
        env:
          TF_VAR_authentik_token: ${{ secrets.AUTHENTIK_TOKEN }}
          OS_APPLICATION_CREDENTIAL_ID: ${{ secrets.LC_CLOUD_APP_CRED_ID }}
          OS_APPLICATION_CREDENTIAL_SECRET: ${{ secrets.LC_CLOUD_APP_CRED_SECRET }}
          AWS_ENDPOINT_URL_S3: ${{ secrets.CEPH_RGW_ENDPOINT }}
          AWS_ACCESS_KEY_ID: ${{ secrets.CEPH_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.CEPH_SECRET_ACCESS_KEY }}
        run: |
          terraform init
          terraform apply -auto-approve

  apply-phase3:
    needs: [detect-changes, apply-phase2]
    if: |
      always() &&
      (needs.apply-phase2.result == 'success' || needs.apply-phase2.result == 'skipped') &&
      needs.detect-changes.outputs.phase3 != '[]'
    strategy:
      matrix:
        stack: ${{ fromJson(needs.detect-changes.outputs.phase3) }}
      fail-fast: false
    concurrency:
      group: apply-${{ matrix.stack }}
      cancel-in-progress: false
    runs-on: ubuntu-latest
    environment: production
    steps: # apply-phase1 と同一
      - uses: actions/checkout@v4
      # 認証情報は GitHub Secrets から取得
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Apply
        working-directory: ${{ matrix.stack }}
        env:
          TF_VAR_authentik_token: ${{ secrets.AUTHENTIK_TOKEN }}
          OS_APPLICATION_CREDENTIAL_ID: ${{ secrets.LC_CLOUD_APP_CRED_ID }}
          OS_APPLICATION_CREDENTIAL_SECRET: ${{ secrets.LC_CLOUD_APP_CRED_SECRET }}
          AWS_ENDPOINT_URL_S3: ${{ secrets.CEPH_RGW_ENDPOINT }}
          AWS_ACCESS_KEY_ID: ${{ secrets.CEPH_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.CEPH_SECRET_ACCESS_KEY }}
        run: |
          terraform init
          terraform apply -auto-approve

  apply-phase4:
    needs: [detect-changes, apply-phase3]
    if: |
      always() &&
      (needs.apply-phase3.result == 'success' || needs.apply-phase3.result == 'skipped') &&
      needs.detect-changes.outputs.phase4 != '[]'
    strategy:
      matrix:
        stack: ${{ fromJson(needs.detect-changes.outputs.phase4) }}
      fail-fast: false
    concurrency:
      group: apply-${{ matrix.stack }}
      cancel-in-progress: false
    runs-on: ubuntu-latest
    # workspace は CODEOWNERS 承認済みのため自動 apply。
    # 管理者権限の Vault ロールは使わず、catalog/projects/ が発行した
    # 制限済み Application Credential（GitHub Secret）を使用する。
    steps:
      - uses: actions/checkout@v4

      - name: プロジェクト名の導出
        id: project
        run: |
          # terraform/workspaces/projects/my-product → my-product
          # terraform/workspaces/teams/infra        → infra
          echo "name=$(echo '${{ matrix.stack }}' \
            | awk -F'/' '{print $NF}')" >> $GITHUB_OUTPUT

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"

      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt

      - name: Apply（制限済み Application Credential を使用）
        working-directory: ${{ matrix.stack }}
        env:
          # catalog/projects/<name>/lc_cloud.tf で発行された Application Credential。
          # Phase 3 の apply 時に github_actions_secret で自動設定される。
          OS_APPLICATION_CREDENTIAL_ID: >-
            ${{ secrets[format('LC_CLOUD_APP_CRED_ID_{0}',
              steps.project.outputs.name)] }}
          OS_APPLICATION_CREDENTIAL_SECRET: >-
            ${{ secrets[format('LC_CLOUD_APP_CRED_SECRET_{0}',
              steps.project.outputs.name)] }}
        run: |
          terraform init
          terraform apply -auto-approve
```

---

## Branch Protection 設定

```text
main ブランチ：
  ├─ require pull request before merging
  │   ├─ required approving reviews: 1
  │   └─ require review from code owners: ON
  ├─ require status checks to pass:
  │   ├─ validate（terraform validate + fmt + セキュリティスキャン）
  │   └─ plan（terraform plan）
  ├─ require branches to be up to date
  └─ restrict who can push: circle-admin のみ
```

---

## セキュリティ考慮事項

| 項目 | 対応 |
| --- | --- |
| 認証情報の保管 | GitHub Actions Secrets に保管（Protected Branch 設定で保護） |
| SOPS 復号鍵 | `SOPS_AGE_KEY` として GitHub Secrets に保管 |
| Tier 1–3 フォルダへの apply | Phase 1–3: `environment: production`（手動承認ゲート） |
| Workspace（Phase 4）の apply | CODEOWNERS 承認済み PR の merge を条件に自動実行 |
| Workspace の OpenStack 認証 | admin 権限を渡さない。`catalog/projects/` が発行した Access Rules 付き Application Credential（GitHub Secret）を使用 |

---

## modules/ 破壊的変更チェック

`terraform/modules/` への変更は全スタックに影響する可能性があります。
PR 時に全スタックの `terraform plan` を実行し、破壊的変更がないことを確認します。
`backend.tf` を持つディレクトリを動的に検出するため、スタックが増えてもワークフローの更新は不要です。

```yaml
# .github/workflows/modules-check.yml
name: Modules Breaking Change Check

on:
  pull_request:
    paths:
      - 'terraform/modules/**'

permissions:
  contents: read
  pull-requests: write

jobs:
  detect-stacks:
    runs-on: ubuntu-latest
    outputs:
      stacks: ${{ steps.detect.outputs.stacks }}
    steps:
      - uses: actions/checkout@v4
      - id: detect
        run: |
          stacks=$(find terraform -name 'backend.tf' -exec dirname {} \; \
            | sort \
            | jq -R -s -c 'split("\n")[:-1]')
          echo "stacks=$stacks" >> $GITHUB_OUTPUT

  plan-all:
    needs: detect-stacks
    strategy:
      matrix:
        stack: ${{ fromJson(needs.detect-stacks.outputs.stacks) }}
      fail-fast: false
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Plan
        id: plan
        working-directory: ${{ matrix.stack }}
        env:
          TF_VAR_authentik_token: ${{ secrets.AUTHENTIK_TOKEN }}
          OS_APPLICATION_CREDENTIAL_ID: ${{ secrets.LC_CLOUD_APP_CRED_ID }}
          OS_APPLICATION_CREDENTIAL_SECRET: ${{ secrets.LC_CLOUD_APP_CRED_SECRET }}
          AWS_ENDPOINT_URL_S3: ${{ secrets.CEPH_RGW_ENDPOINT }}
          AWS_ACCESS_KEY_ID: ${{ secrets.CEPH_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.CEPH_SECRET_ACCESS_KEY }}
        run: |
          terraform init
          terraform plan -no-color 2>&1 | tee plan.txt
        continue-on-error: true
      - name: PR コメントに結果を投稿
        if: steps.plan.outcome == 'failure'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs')
            const plan = fs.readFileSync('${{ matrix.stack }}/plan.txt', 'utf8')
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### ❌ modules 変更による破壊的変更検出: \`${{ matrix.stack }}\`\n\`\`\`\n${plan.slice(-60000)}\n\`\`\``
            })
      - name: Plan 失敗時に CI を失敗させる
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

---

## codeowners-plus バリデーション

`.codeowners` ファイルが正しく配置されているかを PR 時に検証します。

参考：[multimediallc/codeowners-plus](https://github.com/multimediallc/codeowners-plus)

```yaml
# .github/workflows/codeowners-check.yml
name: CODEOWNERS Check

on:
  pull_request:
    paths:
      - 'terraform/workspaces/**'

jobs:
  codeowners-plus:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: multimediallc/codeowners-plus@v1
        with:
          # workspaces 配下の .codeowners を対象に検証
          base_ref: ${{ github.base_ref }}
```

---

## その他のワークフロー

### authentik-dispatch.yml（Authentik からの repository_dispatch 受信）

Authentik の Webhook（`terraform/platform/idp/notification_transports.tf`）が
GitHub の `repository_dispatch` API を叩き、以下の3イベントを処理します。

- `authentik-enrollment-completed`: 新規ユーザーの username・pk を
  `auto-gen-members.yaml` に追記してコミット・プッシュ
- `authentik-source_linked` / `authentik-source_unlinked`（GitHub 連携）:
  `auto-gen-github-usernames.yaml` を更新してコミット・プッシュ

CODEOWNERS 承認を経る通常の PR フローとは異なり、Bot（`authentik-bot`）が
`[skip ci]` 付きで直接 `main` にコミット・プッシュします。詳細は
`03-member-management.md` の「Bot 自動更新フロー」参照。

### ensure-admin-codeowners.yml

`terraform/workspaces/**/.codeowners` の変更を含む PR で、変更された
`.codeowners` ファイルに `@lc-tut/circle-admin` が含まれていなければ
自動で先頭行に追記してコミット・プッシュします（管理者の承認権限が
誤って外れることを防ぐガード）。

---

## ローカル開発

```bash
# 初期セットアップ
terraform init

# 変更確認
terraform plan

# フォーマット
terraform fmt -recursive

# セキュリティスキャン
tfsec .
checkov -d .

# SOPS での秘密ファイル編集
sops terraform/platform/members/active/members_secrets.yaml.enc
```
