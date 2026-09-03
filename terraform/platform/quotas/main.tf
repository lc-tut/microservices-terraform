# グローバルデフォルトクォータ（catalog/projects/ 等が明示的にティアを
# 指定しなかった場合に全プロジェクトへ適用される値）。
#
# openstack_compute_quotaset_v2 / openstack_blockstorage_quotaset_v3 等
# （terraform-provider-openstack が提供）はプロジェクト単位の上書き専用で、
# 「デフォルト値そのもの」を設定する Terraform リソースは存在しない。
# 実体は Nova/Cinder の「quota class」API（PUT .../os-quota-class-sets/default）
# で、これは generic な restapi プロバイダー（Mastercard/terraform-provider-restapi、
# CloudKitty 連携と同じ方針）経由で叩く。
#
# Neutron には同等の API が無い（neutron.conf の static 設定のみ）。
# Neutron は OpenStack インフラ自体の一部として Polaris チームの IaC が管理する範囲
# （01-overview.md「管理対象外」参照）のため、ここでは扱わない。
#
# 実機検証済み（ローカル DevStack・2026-09-03、Nova のみ。この DevStack は
# フットプリント削減のため Cinder 自体を無効化しているので Cinder 側は未検証）:
#   - object_id 指定時の create_path 罠: restapi プロバイダーは object_id を
#     指定していても create_path のデフォルトは "path"（"path/{id}" ではない）。
#     指定しないと CREATE(=PUT) が "/os-quota-class-sets" に飛んで 404 になる。
#     create_path で明示的に "/os-quota-class-sets/default" を指定する。
#   - ignore_server_additions が必須。ただし cloudkitty-service モジュールと違い
#     完全には効かない: レスポンスの fixed_ips/floating_ips/id/injected_file_*/
#     security_group_rules/security_groups は「data のトップレベルに無いフィールド」
#     ではなく「data.quota_class_set の中（ネストした 1 階層下）に無いフィールド」
#     のため、ignore_server_additions のトップレベル比較では吸収しきれない。
#     結果として `terraform plan` はこのリソースについて常に
#     「1 to change」を示し続ける（実機検証済み）。apply 自体は毎回同じ値を
#     PUT するだけなので安全・冪等（実害無し。CI の plan 出力が常にノイズを
#     含む点のみ許容している）。フィールドをこちらの data に明示的に足して
#     完全一致させる案は採用していない: Polaris 実機の現在のデフォルト値を
#     こちらが決め打ちで書き換えてしまうリスクの方が大きいため。
#   - server_groups/server_group_members は quota-class-set API のレスポンスに
#     一切現れない（Nova 側がこのクラスの quota 種別として認識していない模様）。
#     実際に効いているかは未確認。

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
  uri   = "${local.cinder_url}/${var.openstack_admin_project_id}"

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
