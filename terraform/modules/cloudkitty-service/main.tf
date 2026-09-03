# CloudKitty Hashmap モジュールを generic な restapi プロバイダーで管理する。
# 実機で踏んだ罠・2モードの使い分けは README.md 参照。

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
