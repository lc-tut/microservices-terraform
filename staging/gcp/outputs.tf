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
  description = "DevStack の HOST_IP。OS_AUTH_URL は http://<この IP>/identity/"
  value       = var.devstack_internal_ip
}

output "platform_internal_ip" {
  description = "Authentik / Harbor / ingress-nginx が載っている内部 IP"
  value       = var.platform_internal_ip
}

output "tunnels" {
  description = "start-tunnels.sh を実行したあとに手元から開ける URL"
  value = {
    horizon   = "http://localhost:28080/"
    keystone  = "http://localhost:28080/identity/"
    authentik = "http://localhost:29000/if/admin/"
    harbor    = var.enable_harbor ? "http://localhost:28081/" : null
    ingress   = "http://localhost:28000/"
  }
}

output "credentials" {
  description = <<-EOT
    staging の認証情報。terraform output -json credentials で取り出す。
    Authentik の api_token は terraform/platform/idp/ を staging に向けて
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
  }
}
