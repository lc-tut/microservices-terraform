# modules/lc-k8s-app

`workspaces/` から呼び出す汎用 K8s アプリ補助モジュール。
`documents/terraform/16-implementation-phases.md` Phase 5・
`documents/terraform/12-openstack-resources.md`「モジュールライブラリ」を実装したもの。

内包するリソース: `kubernetes_persistent_volume_claim_v1` +
`kubernetes_secret_v1` + `kubernetes_config_map_v1`（いずれも0個以上）。

## 前提

- 呼び出し元(`workspaces/<name>/`)が動く Namespace が、`modules/kubernetes-namespace`
  によって作成済みであること(`var.namespace` で解決)。本モジュールは Namespace
  自体は作らない。
- Pod/Deployment 等のワークロード本体は本モジュールの範囲外
  （PVC・Secret・ConfigMap は用意するが、それらを消費する Workload リソースは
  呼び出し元が別途 `kubernetes_deployment_v1` 等で定義する）。

## 使用例

```hcl
module "app" {
  source    = "../../modules/lc-k8s-app"
  namespace = "my-product"
  name      = "web"

  persistent_volume_claims = {
    data = { storage = "10Gi" }
  }

  secrets = {
    env = {
      data = {
        DATABASE_URL = "postgres://..."
      }
    }
  }

  config_maps = {
    config = {
      data = {
        "app.conf" = file("${path.module}/files/app.conf")
      }
    }
  }
}
```

## 設計メモ

- **Namespace は data source で自動参照**: `var.namespace` を直接
  文字列として各リソースに渡すのではなく、`data.kubernetes_namespace_v1`
  で存在確認した上でその出力を使う。Namespace が未作成のまま apply すると
  ここでエラーになるため、`modules/kubernetes-namespace` の適用漏れに早く気づける。
- **キー付き map で複数リソースをまとめて作成**: `persistent_volume_claims` /
  `secrets` / `config_maps` はいずれも `map(object(...))` で、キーが
  `${var.name}-<key>` の名前サフィックスになる。1アプリが複数の PVC
  （例: `data` と `cache`）を持つケースを1回のモジュール呼び出しで表現できる。
- **`secrets` の値は隠すが `sensitive = true` は付けない**: `kubernetes_secret_v1`
  の `data` 属性自体が provider スキーマ上 `sensitive` なので、変数側で
  追加指定しなくても plan/apply 出力では隠れる。逆に変数側を `sensitive` に
  すると `for_each` のキーに使えなくなる（Terraform の制約）ため付けていない。
  state には平文で残る点は他の Terraform Kubernetes リソースと同じで、
  実際の値は SOPS 等で暗号化した上で呼び出し元から渡す運用を想定している。
- **PVC の `wait_until_bound = false`**: `workspaces/` 適用時点では
  まだ PVC を消費する Pod が存在しない（Workload は別途呼び出し元が定義する
  設計のため）ことが多く、`WaitForFirstConsumer` な StorageClass だと
  Bound 待ちで apply がタイムアウトする。PVC 自体の作成のみを本モジュールの
  責務とし、Bound 確認は求めない。
