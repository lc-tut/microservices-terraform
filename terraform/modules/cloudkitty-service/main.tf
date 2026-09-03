# CloudKitty Hashmap モジュールを generic な restapi プロバイダーで管理する。
# 16-implementation-phases.md の「[P5] CloudKitty の導入方針」を実装したもの。
#
# UPDATE 問題: services/fields/mappings いずれのエンドポイントも PUT を
# サポートしていない（405 Method Not Allowed。当初ドキュメントの想定だった
# 「PUT が 302 を返す」ではなかった。ローカル DevStack で実機検証済み・
# 2026-09-01。Polaris(Kolla / cloudkitty 24.0) でも同じ挙動・2026-09-03）。
# そのため force_new で「値が変わったら更新ではなく destroy → create」にする。
#
# ignore_server_additions が必須: CloudKitty のレスポンスは送信した JSON に
# 無い付加フィールド（例: services なら service_id 自体）を含めて返してくる。
# これを無視しないと次の plan で drift 扱いされ、上記の未対応 PUT を
# 呼ぼうとして失敗する
#
# API パス（実機検証済み）: provider "restapi" の uri にはサービスカタログの
# rating エンドポイント URL をそのまま渡す。そこへ本モジュールが
# "/v1/rating/module_config/hashmap/{services,fields,mappings}" を足す。
#   - DevStack: カタログ URL が "http://host/rating" で終わる
#     → "http://host/rating/v1/rating/module_config/hashmap/services"
#   - Polaris:  スタンドアロン cloudkitty-api を直に公開。カタログ URL は
#     "http://<FIP>:8889" → "http://<FIP>:8889/v1/rating/module_config/hashmap/services"
# どちらも本モジュールの path 定義（先頭 "/v1/rating/..."）で正しく組み立つ。
#
# 2 モード:
#   * field モード（var.field_name != null）:
#       service + field + field の値ごとの mapping（var.mappings）を作る。
#       例: field_name="flavor_id" で フレーバー別単価。
#   * service-level flat モード（var.field_name == null）:
#       service に直付けの flat/rate mapping を 1 個だけ作る（var.service_rate）。
#       例: metric "vcpu" に一律 1.0 Credit/vCPU-hour。
#       documents/terraform/09-costs.md の vCPU/RAM/Block/Floating IP はこちら。

locals {
  field_mode = var.field_name != null
}

resource "restapi_object" "service" {
  provider = restapi.cloudkitty

  path                    = "/v1/rating/module_config/hashmap/services"
  id_attribute            = "service_id"
  ignore_server_additions = true

  data = jsonencode({
    name = var.service_name
  })

  force_new = ["name"]
}

resource "restapi_object" "field" {
  provider = restapi.cloudkitty
  count    = local.field_mode ? 1 : 0

  path                    = "/v1/rating/module_config/hashmap/fields"
  id_attribute            = "field_id"
  ignore_server_additions = true

  data = jsonencode({
    name       = var.field_name
    service_id = restapi_object.service.id
  })

  force_new = ["name", "service_id"]
}

# field モード: field の値ごとの mapping
resource "restapi_object" "mappings" {
  provider = restapi.cloudkitty
  for_each = local.field_mode ? var.mappings : {}

  path                    = "/v1/rating/module_config/hashmap/mappings"
  id_attribute            = "mapping_id"
  ignore_server_additions = true

  # CloudKitty 側の Python 属性名は map_type だが、実際の JSON フィールド名は
  # "type"（wtypes.wsattr(..., name='type')。実機検証済み・2026-09-01）
  data = jsonencode({
    value    = each.key
    cost     = each.value.cost
    type     = each.value.type
    field_id = restapi_object.field[0].id
  })

  # 単価が変わったら更新ではなく作り直す（PUT の 405 問題を回避）
  force_new = ["value", "cost", "type", "field_id"]
}

# service-level flat モード: service 直付けの mapping を 1 個
resource "restapi_object" "service_mapping" {
  provider = restapi.cloudkitty
  count    = local.field_mode ? 0 : 1

  path                    = "/v1/rating/module_config/hashmap/mappings"
  id_attribute            = "mapping_id"
  ignore_server_additions = true

  data = jsonencode({
    cost       = var.service_rate.cost
    type       = var.service_rate.type
    service_id = restapi_object.service.id
  })

  force_new = ["cost", "type", "service_id"]
}
