# terraform/catalog/teams/_template

チームを新規作成するテンプレート。コピーして PR を出す（`05-project-lifecycle.md` 参照）。

## 使い方

```bash
cp -r terraform/catalog/teams/_template terraform/catalog/teams/<team-name>
cd terraform/catalog/teams/<team-name>
```

`backend.tf` の `key` の `_template` 部分を `<team-name>` に変更する:

```diff
- key = "tfstate/terraform/catalog/teams/_template/terraform.tfstate"
+ key = "tfstate/terraform/catalog/teams/<team-name>/terraform.tfstate"
```

`terraform.tfvars` を作成（コミットする、秘密情報は含まれない）:

```hcl
team_name = "<team-name>"
# quota_tier はデフォルト lc-small。変更する場合のみ指定
```

`authentik_token`（sensitive）は GitHub Secrets 経由で CI が渡す
（`AUTHENTIK_TOKEN`、`terraform/platform/idp/` と同じもの）。

## 作られるもの

| リソース | 内容 |
| --- | --- |
| `authentik_group.this` | Authentik Group（SSO・チームメンバー管理の基礎） |
| `openstack_identity_project_v3.this` | OpenStack（Keystone）project |
| `module.quota`（`modules/lc-cloud-quota`） | 上記 project へのクォータ設定 |

`outputs.tf` の `openstack_project_id` を `catalog/projects/` が参照する
（`team_project_id` 変数として明示的に渡す。`terraform_remote_state` は
使わない — 本番 backend が確定するまでの間、他の platform root と同じ
「値は -var で明示的に橋渡しする」方針に揃えている）。

## 予算・Credit 管理について

このテンプレートは Keystone project とクォータのみを作る。「予算上限」
「Credit 残高」といった概念（05-project-lifecycle.md の元の設計にあった
`lc_cloud_budget` 相当）は Keystone にも CloudKitty にも存在せず、
実現するには Middleware API 側の自前実装が要る（`08-billing.md` 参照）。
Phase 6 以降の課題として保留。
