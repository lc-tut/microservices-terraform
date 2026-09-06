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
team_network_name = "<catalog/teams/<team-name>/ の terraform output -raw network_name>"
```

`terraform_remote_state` は使わない。本番 backend が確定するまでの間、
このリポジトリの他の root と同じく「値は -var / tfvars で明示的に橋渡しする」
方針に揃えている（05-project-lifecycle.md の元の設計は `terraform_remote_state`
だったが未採用）。

## 作られるもの

| リソース | 内容 |
| --- | --- |
| `openstack_networking_secgroup_v2.baseline` | プロジェクト分離用のベースライン SG（同一プロジェクト内のみ疎通） |
| `openstack_identity_application_credential_v3.workspace_ci` | Access Rules 付き。Workspace CI/CD 用 |

ネットワークはこの root では作らない。所属チームの `catalog/teams/<team-name>/` が
`/26` を払い出したチーム専用ネットワーク `team-<team-name>` を、そのチームの
全プロジェクトで共有する。この root は受け取った名前を `network_name` として
output し直すだけで、`workspaces/` 側の `modules/lc-vm`・`modules/lc-db` に
`terraform output -raw network_name` を渡す（subnet は指定しない）。

チームのネットワークが埋まったら、チーム側の `subnet_block_count` を増やす
（`catalog/teams/_template/README.md` 参照）。

同じチームのプロジェクト同士は Keystone project もネットワークも共有するため、
**ネットワーク上の境界がありません**。境界はベースライン SG
（`<project>-baseline`、同一 SG メンバーからの ingress のみ許可 + egress 全開放）
で作るので、**このプロジェクトの VM は必ず
`terraform output -raw security_group_id` の SG を付けて起動すること**。
公開したいポートは各プロジェクトが自分で SG ルールを足して開ける。

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
