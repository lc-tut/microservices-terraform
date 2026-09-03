# modules/cloudkitty-service

CloudKitty の Hashmap レーティングモジュールを generic な `restapi` プロバイダーで
管理する Terraform モジュール。`documents/terraform/16-implementation-phases.md` の
「[P5] CloudKitty の導入方針」を実装したもの。

## 実機で判明した罠

**UPDATE 問題**: services/fields/mappings いずれのエンドポイントも PUT を
サポートしていない（405 Method Not Allowed。当初ドキュメントの想定だった
「PUT が 302 を返す」ではなかった。複数の実機で確認済み）。
そのため `force_new` で「値が変わったら更新ではなく destroy → create」にする。

**`ignore_server_additions` が必須**: CloudKitty のレスポンスは送信した JSON に
無い付加フィールド（例: services なら `service_id` 自体）を含めて返してくる。
これを無視しないと次の plan で drift 扱いされ、上記の未対応 PUT を
呼ぼうとして失敗する。

**API パス**: provider `"restapi"` の `uri` にはサービスカタログの rating
エンドポイント URL をそのまま渡す。そこへ本モジュールが
`"/v1/rating/module_config/hashmap/{services,fields,mappings}"` を足す。
カタログ URL の末尾が `/rating` で終わる構成・スタンドアロンの
`cloudkitty-api` を直接公開する構成のどちらでも、本モジュールの path 定義
（先頭 `"/v1/rating/..."`）で正しく組み立つ。

**JSON フィールド名**: CloudKitty 側の Python 属性名は `map_type` だが、
実際の JSON フィールド名は `"type"`（`wtypes.wsattr(..., name='type')`。
実機検証済み）。

## 2 モード

- **field モード**（`var.field_name != null`）: service + field + field の値ごとの
  mapping（`var.mappings`）を作る。例: `field_name="flavor_id"` でフレーバー別単価。
- **service-level flat モード**（`var.field_name == null`）: service に直付けの
  flat/rate mapping を 1 個だけ作る（`var.service_rate`）。
  例: metric `"vcpu"` に一律 1.0 Credit/vCPU-hour。
  `documents/terraform/09-costs.md` の vCPU/RAM/Block/Floating IP はこちら。
