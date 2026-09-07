output "project_id" {
  value = var.project_id
}

output "zone" {
  description = "gcloud compute コマンドに渡すゾーン"
  value       = var.zone
}

output "devstack_instance_name" {
  value = google_compute_instance.devstack.name
}

output "platform_instance_name" {
  value = google_compute_instance.platform.name
}

output "devstack_internal_ip" {
  description = "DevStack の HOST_IP"
  value       = var.devstack_internal_ip
}

output "platform_internal_ip" {
  description = "Authentik / Caddy / Harbor / infra-api が載っている内部 IP"
  value       = var.platform_internal_ip
}

output "dns_records" {
  description = <<-EOT
    **apply のあとに自分で作る DNS レコード。**
    これを作るまで Caddy は Let's Encrypt の証明書を取れず、HTTPS が繋がらない
    （Caddy は取れるまで再試行し続けるので、後から作れば自然に繋がる）。
  EOT
  value = local.publish ? {
    "${local.hostnames.auth}"   = try(google_compute_address.platform_external[0].address, null)
    "${local.hostnames.infra}"  = try(google_compute_address.platform_external[0].address, null)
    "${local.hostnames.harbor}" = try(google_compute_address.platform_external[0].address, null)
    "${local.hostnames.openstack}" = (
      length(var.devstack_allowed_source_ranges) > 0
      ? try(google_compute_address.devstack_external[0].address, null)
      : null
    )
  } : null
}

output "urls" {
  description = "公開している場合の URL。公開していなければ start-tunnels.sh 経由で開く"
  value = local.publish ? {
    authentik = "https://${local.hostnames.auth}/if/admin/"
    infra_api = "https://${local.hostnames.infra}/api/infra/v1/"
    harbor    = var.enable_harbor ? "https://${local.hostnames.harbor}/" : null
    openstack = length(var.devstack_allowed_source_ranges) > 0 ? "http://${local.hostnames.openstack}/identity/" : null
    } : {
    authentik = "http://localhost:29000/if/admin/  (start-tunnels.sh)"
    infra_api = "http://localhost:28000/api/infra/v1/  (start-tunnels.sh)"
    harbor    = var.enable_harbor ? "http://localhost:28081/  (start-tunnels.sh)" : null
    openstack = "http://localhost:28080/identity/  (start-tunnels.sh)"
  }
}

output "oidc" {
  description = <<-EOT
    lcn-infra-api / lcn-billing-api に渡す OIDC の設定。
    terraform/platform/idp/ 側の Provider と一致していなければならない。
  EOT
  value = local.publish ? {
    issuer   = "https://${local.hostnames.auth}/application/o/${var.oidc_client_id}/"
    audience = var.oidc_client_id
    # issuer は Authentik がリクエストの Host から組み立てる。
    # 別のホスト名で発行したトークンは iss が変わり 401 になる
    note = "Authentik には必ず https://${local.hostnames.auth} で入ること"
  } : null
}

output "credentials" {
  description = <<-EOT
    staging の認証情報。terraform output -json credentials で取り出す。
    authentik_api_token は terraform/platform/idp/ を staging に向けて
    apply するときの AUTHENTIK_TOKEN になる。
  EOT
  sensitive   = true
  value = {
    openstack_admin_password = var.devstack_admin_password
    authentik_admin_user     = "akadmin"
    authentik_admin_password = local.authentik_bootstrap_password
    authentik_api_token      = local.authentik_bootstrap_token
    harbor_admin_user        = var.enable_harbor ? "admin" : null
    harbor_admin_password    = var.enable_harbor ? local.harbor_admin_password : null
    infra_api_db_password    = local.infra_db_password
  }
}
