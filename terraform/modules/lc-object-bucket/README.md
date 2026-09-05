# modules/lc-object-bucket

`workspaces/` から呼び出す汎用 Swift コンテナモジュール。
`documents/terraform/16-implementation-phases.md` Phase 5・
`documents/terraform/12-openstack-resources.md`「モジュールライブラリ」を実装したもの。

内包するリソース: `openstack_objectstorage_container_v1` 1つ。

## 使用例

```hcl
module "assets" {
  source = "../../modules/lc-object-bucket"
  name   = "my-product-assets"

  public_read = true

  cors = {
    allow_origin   = ["https://my-product.example.com"]
    expose_headers = ["ETag"]
    max_age        = 3600
  }
}
```

## 設計メモ

- **CORS は `X-Container-Meta-Access-Control-*` メタデータとして実装**:
  Swift の CORS はコンテナメタデータのみで完結する
  （<https://docs.openstack.org/swift/latest/cors.html>）。実在するのは
  `Access-Control-Allow-Origin` / `Access-Control-Max-Age` /
  `Access-Control-Expose-Headers` の3つのみで、`var.cors` はこの3つに
  一対一対応する。`var.metadata` と同キーを指定した場合は `var.cors` 側を
  優先してマージする。
- **lifecycle（オブジェクトの自動期限切れ）は未実装（意図的）**:
  `12-openstack-resources.md` の一覧には「CORS / lifecycle 設定」とあるが、
  Swift にはコンテナ単位の lifecycle 設定は存在しない。オブジェクトの
  自動削除は `X-Delete-At` / `X-Delete-After` をオブジェクトごとの
  アップロード時にクライアント側が指定する仕組みしかなく、コンテナを
  作るだけの本モジュールのスコープでは表現できない。將来
  オブジェクト単位の操作を扱うモジュール（またはワークロード側の
  アップロード処理）で対応する。
- **`container_url` は Swift 独自 URL であり厳密な S3 互換ではない**:
  `12-openstack-resources.md` は「S3 互換 URL を output」としているが、
  Swift の公開 URL（`<object-store endpoint>/<container>`）は Swift 独自の
  形式（例: `.../v1/AUTH_<project_id>/<container>`）。Ceph RGW 等 S3 API も
  同時に提供するバックエンドでは同じコンテナに S3 形式でもアクセスできるが、
  その URL は本モジュールでは解決できない（RGW の S3 エンドポイントは
  Keystone service catalog に別サービスとして載らないことが多いため）。
  `container_url` は `openstack_identity_auth_scope_v3` の
  `service_catalog`（自分自身の認証スコープの情報。admin 権限不要）から
  `object-store` サービスの public endpoint を自動解決する。該当サービスが
  無い、または `var.region` に一致する public endpoint が無い場合は `null`。
- **`public_read`**: `container_read` を明示しない場合の簡易フラグ。
  `true` で `.r:*`（誰でも GET・オブジェクト個別取得は可、一覧取得は不可）を
  設定する。一覧取得も許可したい場合は `container_read = ".r:*,.rlistings"`
  を直接指定する。
