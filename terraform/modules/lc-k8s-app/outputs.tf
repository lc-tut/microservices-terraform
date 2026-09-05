output "namespace" {
  value       = data.kubernetes_namespace_v1.this.metadata[0].name
  description = "解決済みの Namespace名"
}

output "persistent_volume_claim_names" {
  value       = { for k, v in kubernetes_persistent_volume_claim_v1.this : k => v.metadata[0].name }
  description = "persistent_volume_claims のキーごとに作成した PVC 名"
}

output "secret_names" {
  value       = { for k, v in kubernetes_secret_v1.this : k => v.metadata[0].name }
  description = "secrets のキーごとに作成した Secret 名"
}

output "config_map_names" {
  value       = { for k, v in kubernetes_config_map_v1.this : k => v.metadata[0].name }
  description = "config_maps のキーごとに作成した ConfigMap 名"
}
