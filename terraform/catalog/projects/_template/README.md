# terraform/catalog/projects/_template

プロジェクトを新規作成するテンプレート。コピーして PR を出す（`05-project-lifecycle.md` 参照）。
先に対応する `catalog/teams/<team-name>/` が apply 済みであること。

## 使い方

```bash
cp -r terraform/catalog/projects/_template terraform/catalog/projects/<project-name>
cd terraform/catalog/projects/<project-name>
```

`backend.tf` の `key` の `_template` 部分を `<project-name>` に変更する。

`terraform.tfvars` を作成:

```hcl
project_name    = "<project-name>"
team_project_id = "<catalog/teams/<team-name>/ の terraform output -raw openstack_project_id>"
subnetpool_id          = "<platform/openstack/network/ の terraform output -raw subnetpool_id>"
vpc_gateway_router_id  = "<platform/openstack/network/ の terraform output -raw vpc_gateway_router_id>"
```

`terraform_remote_state` は使わない。本番 backend が確定するまでの間、
このリポジトリの他の root と同じく「値は -var / tfvars で明示的に橋渡しする」
方針に揃えている（05-project-lifecycle.md の元の設計は `terraform_remote_state`
だったが未採用）。

## 作られるもの

| リソース | 内容 |
| --- | --- |
| `openstack_networking_network_v2.project` | プロジェクト専用 private network |
| `openstack_networking_subnet_v2.project` | subnetpool から /24 を払い出し |
| `openstack_networking_router_interface_v2.project` | VPC Gateway への接続 |
| `openstack_identity_application_credential_v3.workspace_ci` | Access Rules 付き。Workspace CI/CD 用 |

DNS Zone・LB Pool はこの Phase では作らない（`16-implementation-phases.md` の
`[P10]`、Phase 8・Phase 9 で扱う）。Harbor Project 連携も未実装
（`terraform/platform/harbor/` が Harbor 本体側の設定を持つが、
プロジェクト単位の Harbor Project 作成はまだ無い）。

## GitHub Actions Secret への自動登録について（未実装・意図的に保留）

05-project-lifecycle.md の元の設計は `github_actions_secret` リソースで
Application Credential を自動的に GitHub Secrets へ登録する想定だった。
現状 GitHub Actions 側で `workspaces/` を CI/CD apply する仕組みがまだ
整備できていないため、この自動登録は入れていない。credential は
Terraform state にのみ保存され（他の secret と同じ方針、平文コミットなし）、
`terraform output -raw app_cred_secret` で手動取得して使う。
GitHub Actions 側の CI/CD が整備できたら `github_actions_secret` を
追加する（Phase 5・6 の課題）。

## 前提: Application Credential の発行に project スコープが要る

`openstack_identity_application_credential_v3` はセルフサービス限定のリソースで、
admin が他プロジェクト用の credential を代理発行することはできない。そのため
`providers.tf` は `team_project_id` にスコープしなおした2つ目の provider
（`openstack.team_scoped`）を用意している。これが機能するには、対応する
`catalog/teams/<team-name>/` が自動化アカウント（デフォルト `admin`）に
このプロジェクトの `member` ロールを付与済みであること（`teams/_template/lc_cloud.tf` 参照）。
