# modules/lc-role-map

抽象ロール（`owner` / `member` / `viewer`）を各システムのネイティブロール名へ
写すだけの、**provider を持たない純ロジックモジュール**です。
設計の背景は `documents/terraform/18-access-control.md` を参照してください。

このモジュールが存在する理由はひとつで、
**写像表をリポジトリ全体で 1 箇所にしか置かないため**です。
Harbor や K8s の実装を追加するときも、写像を各 `catalog/` にコピーせず
ここに output を足して参照してください。

## 使い方

```hcl
module "roles" {
  source     = "../../../modules/lc-role-map"
  scope_type = "team"
  scope_name = var.team_name
}

# => module.roles.group_names  = { owner = "team-infra-owner", ... }
# => module.roles.keystone_role = { owner = "member", member = "member", viewer = "reader" }
```

## 出力

| output | 内容 |
| --- | --- |
| `roles` | `["owner", "member", "viewer"]`。`for_each` のキーに使う |
| `grants` | アドオン権限の語彙。`members.yaml` の `grants` はこの集合に含まれる必要がある |
| `group_names` | Authentik / Keystone 共通のグループ名（`team-<name>-<role>` / `proj-<name>-<role>`） |
| `keystone_role` | Keystone ロール名。`owner` と `member` はどちらも `member` |
| `harbor_role` | Harbor のプロジェクトメンバーロール名 |
| `k8s_role` | Kubernetes 組み込み ClusterRole 名 |
| `github_team` | GitHub Team 名。`project` スコープと `viewer` は `null` |

## 注意

- **`keystone_role` の `owner` と `member` は同じ値（`member`）です。**
  Keystone の既定ロールが `admin` / `member` / `reader` の 3 つしかないためで、
  写像の手抜きではありません。`owner` の特別さは GitHub の承認権・Harbor・K8s・
  `owners.yaml` の編集権のほうで表現されます。
- **`reader` ロールは Keystone に存在している必要があります**（Ussuri 以降の既定ロール）。
  古い環境で未定義の場合は `data.openstack_identity_role_v3` の参照時にエラーになります。
- `scope_name` は Authentik・Keystone・Harbor・GitHub のすべてで安全に使える文字種
  （英小文字・数字・ハイフン）に制限しています。
