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
  id-token: write    # Vault OIDC 認証用

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

      # Vault から認証情報を取得（OIDC、長期トークン不要）
      - uses: hashicorp/vault-action@v3
        with:
          url: https://vault.lc-cloud.example.internal
          method: jwt
          role: github-terraform-plan
          secrets: |
            secret/data/terraform/authentik   AUTHENTIK_TOKEN ;
            secret/data/terraform/lc-cloud    LC_CLOUD_TOKEN

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
  id-token: write

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
      - uses: hashicorp/vault-action@v3
        with:
          url: https://vault.lc-cloud.example.internal
          method: jwt
          role: github-terraform-apply
          secrets: |
            secret/data/terraform/authentik   AUTHENTIK_TOKEN ;
            secret/data/terraform/lc-cloud    LC_CLOUD_TOKEN
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Apply
        working-directory: ${{ matrix.stack }}
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
      - uses: hashicorp/vault-action@v3
        with:
          url: https://vault.lc-cloud.example.internal
          method: jwt
          role: github-terraform-apply
          secrets: |
            secret/data/terraform/authentik   AUTHENTIK_TOKEN ;
            secret/data/terraform/lc-cloud    LC_CLOUD_TOKEN
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Apply
        working-directory: ${{ matrix.stack }}
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
      - uses: hashicorp/vault-action@v3
        with:
          url: https://vault.lc-cloud.example.internal
          method: jwt
          role: github-terraform-apply
          secrets: |
            secret/data/terraform/authentik   AUTHENTIK_TOKEN ;
            secret/data/terraform/lc-cloud    LC_CLOUD_TOKEN
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"
      - name: SOPS 復号キー設定
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
      - name: Apply
        working-directory: ${{ matrix.stack }}
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
| 長期 API トークン | 使わない。Vault OIDC で都度取得 |
| SOPS 復号鍵 | GitHub Actions Secrets に保管（Protected） |
| plan ロールと apply ロール | Vault で権限分離（plan は読み取り専用） |
| Tier 1–3 フォルダへの apply | Phase 1–3: `environment: production`（手動承認ゲート） |
| Workspace（Phase 4）の apply | CODEOWNERS 承認済み PR の merge を条件に自動実行 |
| Workspace の OpenStack 認証 | Vault 管理者権限を渡さない。`catalog/projects/` が発行した Access Rules 付き Application Credential（GitHub Secret）を使用 |

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
  id-token: write

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
      - uses: hashicorp/vault-action@v3
        with:
          url: https://vault.lc-cloud.example.internal
          method: jwt
          role: github-terraform-plan
          secrets: |
            secret/data/terraform/authentik   AUTHENTIK_TOKEN ;
            secret/data/terraform/lc-cloud    LC_CLOUD_TOKEN
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
