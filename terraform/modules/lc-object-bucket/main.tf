# container_url 用に service catalog を自己参照する。identity_endpoint_v3
# data source は admin 権限が要る一方、こちらは自分自身の認証スコープを
# 見るだけなのでプロジェクトスコープの provider からでも使える。
data "openstack_identity_auth_scope_v3" "current" {
  name = "current"
}

locals {
  object_store_catalog_entries = [
    for entry in data.openstack_identity_auth_scope_v3.current.service_catalog :
    entry if entry.type == "object-store"
  ]

  object_store_endpoints = length(local.object_store_catalog_entries) > 0 ? [
    for endpoint in local.object_store_catalog_entries[0].endpoints :
    endpoint if endpoint.interface == "public" && (var.region == null || endpoint.region == var.region)
  ] : []

  cors_metadata = var.cors == null ? {} : merge(
    var.cors.allow_origin == null ? {} : { "Access-Control-Allow-Origin" = join(" ", var.cors.allow_origin) },
    var.cors.max_age == null ? {} : { "Access-Control-Max-Age" = tostring(var.cors.max_age) },
    var.cors.expose_headers == null ? {} : { "Access-Control-Expose-Headers" = join(" ", var.cors.expose_headers) },
  )
}

resource "openstack_objectstorage_container_v1" "this" {
  region = var.region
  name   = var.name

  container_read  = var.container_read != null ? var.container_read : (var.public_read ? ".r:*" : null)
  container_write = var.container_write

  versioning     = var.versioning
  storage_policy = var.storage_policy
  storage_class  = var.storage_class
  content_type   = var.content_type
  force_destroy  = var.force_destroy

  # cors を var.metadata より後にマージして、同キー指定時は cors 側を優先する
  metadata = merge(var.metadata, local.cors_metadata)
}
