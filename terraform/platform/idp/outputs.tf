# idp/ の他のリソースはこれまで出力を必要とする消費者が無かったため outputs.tf が
# 無かった。Harbor OIDC 連携（terraform/platform/harbor/）が最初の消費者。

output "harbor_oidc_client_id" {
  value       = try(authentik_provider_oauth2.harbor[0].client_id, null)
  description = "terraform/platform/harbor/ の oidc_client_id にそのまま渡す値"
}

output "harbor_oidc_client_secret" {
  value       = try(authentik_provider_oauth2.harbor[0].client_secret, null)
  description = "terraform/platform/harbor/ の oidc_client_secret にそのまま渡す値"
  sensitive   = true
}

output "harbor_oidc_issuer" {
  value       = var.harbor_url != "" ? "${var.authentik_url}/application/o/${authentik_application.harbor[0].slug}/" : null
  description = "terraform/platform/harbor/ の oidc_endpoint にそのまま渡す値"
}
