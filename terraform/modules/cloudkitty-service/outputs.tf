output "service_id" {
  value = restapi_object.service.id
}

output "field_id" {
  value = one(restapi_object.field[*].id)
}

output "mapping_ids" {
  description = "field モード: field 値ごとの mapping id。service-level モード: 単一 mapping を \"_service\" キーで返す。"
  value = local.field_mode ? {
    for k, v in restapi_object.mappings : k => v.id
    } : {
    _service = one(restapi_object.service_mapping[*].id)
  }
}
