# terraform/catalog/billing-accounts/personal/_template

個人クォータをデフォルト（`lc-micro`）から変更する場合のみコピーして使う
テンプレート（`08-billing.md` 参照）。デフォルトのままで良ければファイル自体
不要。

## 使い方

```bash
cp -r terraform/catalog/billing-accounts/personal/_template terraform/catalog/billing-accounts/personal/<username>
cd terraform/catalog/billing-accounts/personal/<username>
```

`backend.tf` の `key` の `_template` を `<username>` に変更し、`terraform.tfvars`
を作成:

```hcl
username   = "<username>"
quota_tier = "lc-small"  # 例: micro から引き上げる場合
```

## 前提（未実装）

このテンプレートは `data "openstack_identity_project_v3" { name = var.username }`
で個人 project を参照するが、**個人 OpenStack project をメンバー入会時に
自動作成する仕組み自体、まだ実装されていない**（`platform/members/` は
Authentik ユーザーの作成のみ）。対応する project が存在しない状態でこの
テンプレートを apply しても data lookup が失敗する。個人 project 自動作成の
実装は今後の課題（`08-billing.md`「個人請求アカウント」参照）。

予算・Credit 残高の管理（元の設計にあった `lc_cloud_budget`）も同様に
Middleware API 側の自前実装が必要で未着手（Phase 6 以降）。
