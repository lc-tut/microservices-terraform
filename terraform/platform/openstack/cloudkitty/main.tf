# CloudKitty の Hashmap 課金ルール（Credit 建ての正式単価）を IaC 管理する。
# 実機構成・service 名の対応・認証方式は README.md 参照。

data "openstack_identity_auth_scope_v3" "current" {
  name         = "current"
  set_token_id = true
}

locals {
  cloudkitty_endpoint = [
    for svc in data.openstack_identity_auth_scope_v3.current.service_catalog :
    svc if svc.type == "rating"
  ][0]
  cloudkitty_url = [
    for ep in local.cloudkitty_endpoint.endpoints :
    ep.url if ep.interface == "public"
  ][0]
}

provider "restapi" {
  alias = "cloudkitty"
  uri   = local.cloudkitty_url

  headers = {
    "X-Auth-Token" = data.openstack_identity_auth_scope_v3.current.token_id
    "Content-Type" = "application/json"
  }

  write_returns_object = true
  create_method        = "POST"
  update_method        = "PUT"
}

# --- Credit 建て正式単価（documents/terraform/09-costs.md）---
# 1 Credit = 1 vCPU-hour を基準。period=3600s なので qty はそのまま
# 「その 1 時間の平均使用量」を表し、単価×qty が Credit/時になる。

module "vcpu" {
  source       = "../../../modules/cloudkitty-service"
  service_name = "vcpu"
  service_rate = { cost = "1.000000", type = "flat" } # 1.000 Credit / vCPU-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

module "memory" {
  source       = "../../../modules/cloudkitty-service"
  service_name = "memory"
  service_rate = { cost = "0.250000", type = "flat" } # 0.250 Credit / GB-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

module "volume" {
  source       = "../../../modules/cloudkitty-service"
  service_name = "volume"
  service_rate = { cost = "0.002000", type = "flat" } # 0.002 Credit / GB-hour（Cinder）
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

module "floating_ip" {
  source       = "../../../modules/cloudkitty-service"
  service_name = "floating_ip"
  service_rate = { cost = "0.500000", type = "flat" } # 0.500 Credit / IP-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

# オブジェクトストレージ（0.0005 Credit/GB-hour, 09-costs.md）は
# Swift/S3(RGW) 未導入のため未設定。RGW 導入時に metric を足してここに追加する。
