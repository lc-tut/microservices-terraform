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

`owners.yaml` に owner を **2 人以上**書く（1 人だと plan が失敗する。理由は下記）。

## 作られるもの

| リソース | 内容 |
| --- | --- |
| `authentik_group.this` | チーム包括グループ（識別・通知用。権限は持たない） |
| `authentik_group.role` | ロール別グループ `team-<name>-{owner,member,viewer}` |
| `openstack_identity_group_v3.role` | 上記と同名の Keystone グループ |
| `openstack_identity_role_assignment_v3.team` | Keystone グループ → project へのロール付与 |
| `openstack_identity_project_v3.this` | OpenStack（Keystone）project |
| `module.quota`（`modules/lc-cloud-quota`） | 上記 project へのクォータ設定 |

## 権限管理（`owners.yaml` / `members.yaml` / `team.yaml`）

設計の全体像は `documents/terraform/18-access-control.md` を参照。
このテンプレートで押さえるべき点は 3 つ。

- **`owners.yaml` と `members.yaml` は別ファイル**。CODEOWNERS の粒度がファイル単位なので、
  owner の増減だけを circle-admin 承認必須にするにはこの分割が必要になる。
- **このスタックは「誰がグループに入るか」を作らない。** 所属は
  `terraform/platform/members/team_memberships.tf` が唯一の書き込み口になる。
  Authentik の所属 API は user 側・group 側のどちらも「集合の丸ごと置き換え」なので、
  両方から書くと 2 つのスタックが互いの変更を消し合う無限 drift になる。
- **plan 時に不変条件を検証する**（`terraform_data.access_invariants`）。
  owner 2 人以上・id の重複なし・`role` は `member`/`viewer` のみ・`grants` は
  `modules/lc-role-map` の語彙内・**id がメンバー台帳に存在し `active` であること**。
  最後の 1 つは `terraform/platform/members/*/*/members.yaml` を直接読んで確認しており、
  「卒業した人の権限が残る」事故を plan の時点で止められる。

> **apply 順序**: 新チームはこのスタックを先に apply してから
> `terraform/platform/members/` を apply する（あちらはグループを名前で `data` 参照するため）。
>
> **前提**: Keystone に `reader` ロールが存在すること（Ussuri 以降の既定ロール）。
> 無い環境では `data.openstack_identity_role_v3.role_by_name` の解決に失敗する。

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
