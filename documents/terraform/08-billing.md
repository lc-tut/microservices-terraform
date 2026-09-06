# 請求アカウント管理

## 概要

LC-Cloud 上の請求アカウントはデフォルト設定で自動プロビジョニングされます。
クォータ・予算をデフォルトから変更したい場合のみ `catalog/billing-accounts/` にファイルを追加します。

```text
メンバー登録 / チーム作成
  │
  └─ LC-Cloud プロジェクトが自動作成（デフォルトクォータ適用）
       │
       └─ カスタム設定が必要な場合のみ
            catalog/billing-accounts/<type>/<name>/ を追加して PR
```

デフォルトクォータは `terraform/platform/openstack/quotas/` で管理者が設定します（OpenStack グローバルデフォルト）。
クォータティアの詳細は `07-quota.md` を参照してください。

| 種別 | デフォルトティア | デフォルト予算 |
|---|---|---|
| 個人 | `lc-micro` | 5,000 Credits/月 |
| チーム | `lc-small` | 15,000 Credits/月 |

コスト定義・Credit 単価・CloudKitty 設定の詳細は `09-costs.md` を参照してください。

---

## 請求アカウントの種別

### 個人請求アカウント

| 項目 | 内容 |
|---|---|
| 作成タイミング | `platform/members/` が台帳の `active` メンバーから自動作成する |
| Keystone project 名 | `user-<lcn_id>`（`user-lcn-9a2bb6e30171` のようにハイフン区切り） |
| オーナー | 本人だけが入る Authentik グループ `user-<lcn_id>-owner` 経由 |
| 共有 | 不可。1 project に 1 人しか入らない |
| デフォルトクォータ | `lc-micro` |
| カスタマイズ | `catalog/billing-accounts/personal/<lcn_id>/` を作成して PR（管理者承認） |
| 無効化 | 台帳で `ob-og` / `alumni` に移すと project ごと消える |

project 名とグループ名のキーに username ではなく `lcn_id` を使うのは、
username は本人が enrollment 後に変更できるためです。username をキーにすると
改名した時点で project 名と実体がずれます。

既定では **Keystone project とクォータ、グループとロール付与だけ**を作ります。
ネットワークと Application Credential は作りません。外向き通信は単一の
VPC Gateway router に集約する設計のため人数分の router interface を張ると
そこが詰まること、Application Credential は 1 つあたり約 40 本の access rule を
持つことが理由です。個人でネットワークが必要になったら、そのとき申請して足します。

### チーム請求アカウント

| 項目 | 内容 |
|---|---|
| 作成タイミング | チーム作成時に LC-Cloud プロジェクトを自動作成 |
| オーナー | 申請チーム（複数チームの共同参照も可） |
| 共有 | **可**。複数チームやプロジェクトが同一アカウントを参照できる |
| デフォルトクォータ | `lc-small`（`platform/openstack/quotas/` で設定） |
| カスタマイズ | `catalog/billing-accounts/teams/<name>/` を作成して PR（管理者承認） |
| 無効化 | 所属チームがすべてアーカイブされた後、管理者が apply で削除 |

---

## 権限モデル

権限は Authentik グループに張り、Keystone の同名グループへ federation mapping で
写します。個人にロールを直接張ることはしません（`18-access-control.md`）。

| | Keystone project | グループ | 入る人 |
| --- | --- | --- | --- |
| 個人 | `user-<lcn_id>` | `user-<lcn_id>-owner` | 本人のみ |
| チーム | `team-<name>` | `team-<name>-{owner,member,viewer}` | チームのメンバー |

個人 project は 1 人しか入らないため、ロールは `owner` だけです。
チームは 3 ロールを使い分けます。

請求アカウントがどの project を課金対象にするかは、請求アカウント側が
直接指定します（`14-middleware-architecture.md` の `billing_account_resources`）。
「チームの下に請求アカウントがぶら下がる」という所有関係ではないため、
1 つの請求アカウントで複数チームをまとめることも、チーム内のワークスペースだけを
別会計にすることもできます。

---

## Terraform での実装（カスタマイズ時のみ）

請求アカウント（予算上限・Credit 残高・複数コスト源の合算）を担うのは
**billing-api** です。設計は `14-middleware-architecture.md` にあります。

CloudKitty が担うのは「使用量 × 単価 = 金額」の計算までで、OpenStack 用と
Kubernetes 用の 2 インスタンスがそれぞれ独立に計算します。請求アカウント単位で
両者を合算し、予算の 80% / 100% を判定するのは billing-api の役目です。
Terraform から操作するのは CloudKitty の Hashmap レーティングルール
（`platform/openstack/cloudkitty/`・`modules/cloudkitty-service/`）と
クォータ（`modules/lc-cloud-quota`）です。

`catalog/billing-accounts/` はクォータを既定から変えたい場合にだけ作ります。
project の実体は個人なら `platform/members/`、チームなら `catalog/teams/<name>/`
が既に作っているので、ここでは `data` で参照します。

### 個人アカウントのカスタマイズ

```hcl
# terraform/catalog/billing-accounts/personal/lcn_9a2bb6e30171/main.tf

# name だけで引くと同名の project が別 domain にあった場合にそちらを
# 引き当ててしまうため、domain_id を必ず指定する
data "openstack_identity_project_v3" "this" {
  name      = "user-${replace(var.lcn_id, "_", "-")}"
  domain_id = "default"
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.openstack_identity_project_v3.this.id
  tier       = var.quota_tier

  quota_override = var.quota_override
}
```

`var.lcn_id` は台帳のキー（`lcn_9a2bb6e30171`）です。`quota_tier` の既定は
`lc-micro`、`quota_override` でフィールド単位の上書きができます
（`07-quota.md`）。

### チームアカウントのカスタマイズ

```hcl
# terraform/catalog/billing-accounts/teams/infra/main.tf

data "openstack_identity_project_v3" "this" {
  name      = "team-${var.team_name}"
  domain_id = "default"
}

module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = data.openstack_identity_project_v3.this.id
  tier       = var.quota_tier

  quota_override = var.quota_override
}
```

既定は `lc-small` で、validation により `lc-micro` は選べません。

---

## フォルダ構成

```text
terraform/catalog/billing-accounts/
├── personal/                   # 個人クォータのカスタマイズ（必要な場合のみ）
│   ├── _template/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── lcn_9a2bb6e30171/       # デフォルトから変更が必要なメンバーのみ
│       ├── main.tf
│       └── variables.tf
└── teams/                      # チームクォータのカスタマイズ（必要な場合のみ）
    ├── _template/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── infra/                  # デフォルトから変更が必要なチームのみ
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## 管理フロー

### クォータ・予算のカスタマイズ申請

```text
1. _template/ をコピーして catalog/billing-accounts/<type>/<name>/ を作成
2. 変更したい項目（quota_tier / quota_override / budget_limit）のみ設定
3. PR → 管理者承認 → apply
```

### デフォルトクォータの変更（全体に影響）

```text
terraform/platform/openstack/quotas/ の OpenStack グローバルデフォルトを変更して PR
→ 管理者承認 → apply
→ catalog/billing-accounts/ で個別設定していないすべてのアカウントに反映
```
