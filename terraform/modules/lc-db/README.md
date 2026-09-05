# modules/lc-db

`workspaces/` から呼び出す汎用 Trove DB モジュール。
`documents/terraform/16-implementation-phases.md` Phase 5・
`documents/terraform/12-openstack-resources.md`「モジュールライブラリ」を実装したもの。

内包するリソース: `openstack_db_instance_v1` + `openstack_db_database_v1`
（0個以上）+ `openstack_db_user_v1`（0個以上）。

## 前提

- **実機 Polaris への Trove 導入が必要**。2026-09-05 に導入・実機
  エンドツーエンド検証済み（Trove 本体・ゲストイメージ・mysql/8.0 データストア・
  `openstack database instance create` での起動まで確認済み）。
  導入手順（kolla-ansible の設定変更・ゲストイメージ登録）は
  `documents/terraform/17-production-runbook.md` Phase 5 節、実機値・
  ハマった点は `local/polaris-access.md` にまとめてある。
  このモジュールは Trove 側のデータストア登録（`trove-manage
  datastore_version_update` 済み）が終わった状態を前提に、
  「プロジェクトが Trove インスタンスを作る」部分だけを扱う。
- 呼び出し元(`workspaces/<name>/`)が動く project に、`catalog/projects/<name>/` が
  作成した同名の network が存在すること(`var.project_name` で解決)。
- **`var.flavor` の disk サイズはゲストイメージのファイルサイズ以上にすること**
  （実機で確認済みの罠）。disk サイズがイメージより小さいと Nova が
  `Flavor's disk is too small for requested image` で instance-create 自体を
  拒否する。このリポジトリでビルドしたゲストイメージ（約1.4GB）に対しては
  `m1.tiny`（disk=1GB）は不可、`m1.small`（disk=20GB）以上を使うこと。

## 使用例

```hcl
module "db" {
  source            = "../../modules/lc-db"
  name              = "my-app-db"
  project_name      = "my-product"
  flavor            = "m1.medium"
  volume_size_gb    = 10
  datastore_type    = "mysql"
  datastore_version = "8.0" # 実機で trove-manage datastore_version_update 済みの値

  databases = [
    { name = "myapp" }
  ]

  users = {
    myapp = {
      password  = var.db_password # SOPS 等で暗号化した値を渡す想定
      databases = ["myapp"]
    }
  }
}
```

## 設計メモ

- **flavor は Nova flavor 名から自動解決**: OpenStack provider には Trove
  flavor を名前で引く data source が存在しないため、`modules/lc-vm` と同様に
  `data.openstack_compute_flavor_v2`（Nova flavor）で名前解決している。
  実機 Polaris で `openstack flavor list`（Nova）と
  `openstack database flavor list`（Trove）の ID が完全一致することを確認済み
  （2026-09-05、`local/polaris-access.md` 参照）。ただしこれは Trove の
  flavor 一覧が Nova flavor から導出される実装に依存しており、環境ごとに
  保証されるものではない。一致しない環境では `var.flavor_id` に Trove
  flavor ID を直接指定する（`var.flavor` より優先）。
- **database/user はインスタンス本体と独立したリソース**: `modules/lc-vm`
  が boot volume を独立リソース化しているのと同じ理由。
  `openstack_db_instance_v1` の inline `database`/`user` ブロックは
  変更のたびにインスタンス再作成を要求する（provider ドキュメントに
  明記）が、`openstack_db_database_v1`/`openstack_db_user_v1` は
  単体で追加・削除できる。
- **password は state に平文で残る**: `openstack_db_user_v1` は provider
  ドキュメントに明記されている通り sensitive 属性ではない。SOPS 等で
  暗号化した値を variable 経由で渡す運用を想定している。
- **`openstack_db_user_v1` に host 引数は無い**: 全ホストからの接続を
  許可する Trove のデフォルト動作のまま（provider が対応していないため
  制限できない）。
- **ネットワーク到達性**: `documents/terraform/17-production-runbook.md`
  Phase 5-4 で懸念していた「multi-tenant モードだとゲスト VM が
  control plane の RabbitMQ に届かない」問題は、実機 Polaris では
  発生しないことを確認済み（floating IP 網と内部 API 網が同一セグメントで、
  プロジェクトのルーターの SNAT 経由で元々到達できるため）。
  `enable_trove_singletenant` はデフォルト(false)のまま運用している。
  他環境でこのモジュールを使う場合は、この前提（プロジェクトネットワークから
  RabbitMQ への到達性）が成り立つか個別に確認すること。
