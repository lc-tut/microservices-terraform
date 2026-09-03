# グローバルデフォルトクォータ（catalog/projects/ 等が明示的にティアを
# 指定しなかった場合に全プロジェクトへ適用される値）。
# 実装方式・実機で踏んだ罠は README.md 参照。

# openstack provider と同じ認証情報でトークンを取得し、restapi provider に渡す。
# set_token_id = true にしないと token_id が空のまま返る
data "openstack_identity_auth_scope_v3" "current" {
  name         = "current"
  set_token_id = true
}

locals {
  # 個人・チームどちらの明示的な apply も無いプロジェクトに適用される
  # 最小限の安全側デフォルト。値は modules/lc-cloud-quota の lc-micro と
  # 同じにしている（変更時は両方を更新すること）
  nova_default = {
    instances            = 3
    cores                = 2
    ram                  = 4096
    server_groups        = 3
    server_group_members = 5
    key_pairs            = 10
    metadata_items       = 128
  }

  cinder_default = {
    volumes              = 5
    snapshots            = 5
    gigabytes            = 50
    per_volume_gigabytes = 50
    backups              = 3
    backup_gigabytes     = 50
  }

  nova_endpoint = [
    for svc in data.openstack_identity_auth_scope_v3.current.service_catalog :
    svc if svc.type == "compute"
  ][0]
  nova_url = [
    for ep in local.nova_endpoint.endpoints :
    ep.url if ep.interface == "public"
  ][0]

  cinder_endpoint = [
    for svc in data.openstack_identity_auth_scope_v3.current.service_catalog :
    svc if svc.type == "block-storage" || svc.type == "volumev3"
  ][0]
  cinder_url = [
    for ep in local.cinder_endpoint.endpoints :
    ep.url if ep.interface == "public"
  ][0]
}

provider "restapi" {
  alias = "nova"
  uri   = local.nova_url

  headers = {
    "X-Auth-Token" = data.openstack_identity_auth_scope_v3.current.token_id
    "Content-Type" = "application/json"
  }

  write_returns_object = true
  create_method        = "PUT"
  update_method        = "PUT"
}

provider "restapi" {
  alias = "cinder"
  # project_id を URL に含めない。Cinder API v3.71（実機確認済み・2026-09-04）は
  # project-id-less な URL（token のスコープでプロジェクトを判定する方式）で、
  # "${cinder_url}/${project_id}/..." を付けると全エンドポイントが
  # 400 "Malformed request url" になる（quota-class-sets 固有の問題ではなく
  # types 等の基本エンドポイントでも再現）。var.openstack_admin_project_id は
  # このため未使用（older な project-id 必須の Cinder に対応する場合のみ復活させる）。
  uri = local.cinder_url

  headers = {
    "X-Auth-Token" = data.openstack_identity_auth_scope_v3.current.token_id
    "Content-Type" = "application/json"
  }

  write_returns_object = true
  create_method        = "PUT"
  update_method        = "PUT"
}

resource "restapi_object" "nova_quota_class_default" {
  provider = restapi.nova

  path      = "/os-quota-class-sets"
  object_id = "default"

  # object_id 指定時、restapi プロバイダーの create_path のデフォルトは
  # "path"（"path/{id}" ではない）。singleton リソースの CREATE(=PUT) を
  # 確実に "/os-quota-class-sets/default" に向けるため明示する。
  # 未指定だと "/os-quota-class-sets" への PUT になり 404（実機検証済み・
  # 2026-09-03、ローカル DevStack）。read/update/destroy は
  # デフォルトの "path/{id}" のままで正しく "/os-quota-class-sets/default" になる。
  create_path             = "/os-quota-class-sets/default"
  ignore_server_additions = true

  data = jsonencode({
    quota_class_set = local.nova_default
  })

  # このリソースは常に存在するシングルトン（"default" クラス）なので
  # destroy は実質的に無効化する（DELETE は Nova API がサポートしていない）
  destroy_method = "PUT"
  destroy_data = jsonencode({
    quota_class_set = local.nova_default
  })
}

resource "restapi_object" "cinder_quota_class_default" {
  provider = restapi.cinder

  path                    = "/os-quota-class-sets"
  object_id               = "default"
  create_path             = "/os-quota-class-sets/default"
  ignore_server_additions = true

  data = jsonencode({
    quota_class_set = local.cinder_default
  })

  destroy_method = "PUT"
  destroy_data = jsonencode({
    quota_class_set = local.cinder_default
  })
}
