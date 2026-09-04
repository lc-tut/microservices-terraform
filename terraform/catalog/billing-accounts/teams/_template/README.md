# terraform/catalog/billing-accounts/teams/_template

チームクォータをデフォルト（`lc-small`）から変更する場合のみコピーして使う
テンプレート（`08-billing.md` 参照）。デフォルトのままで良ければファイル自体不要。
先に対応する `catalog/teams/<team-name>/` が apply 済みであること
（`openstack_identity_project_v3` を name で lookup するため）。

## 使い方

```bash
cp -r terraform/catalog/billing-accounts/teams/_template terraform/catalog/billing-accounts/teams/<team-name>
cd terraform/catalog/billing-accounts/teams/<team-name>
```

`backend.tf` の `key` の `_template` を `<team-name>` に変更し、`terraform.tfvars`
を作成:

```hcl
team_name  = "<team-name>"
quota_tier = "lc-standard-8"  # 例: small から引き上げる場合
```

## 予算・Credit 管理について

`catalog/teams/_template/README.md` と同じ。予算上限・Credit 残高の管理
（元の設計にあった `lc_cloud_budget`）は Middleware API 側の自前実装が
必要で未着手（Phase 6 以降、`08-billing.md` 参照）。
