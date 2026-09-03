output "cloudkitty_url" {
  description = "サービスカタログの rating(public) エンドポイント URL"
  value       = local.cloudkitty_url
}

output "hashmap_service_ids" {
  description = "作成した Hashmap service の id"
  value = {
    vcpu        = module.vcpu.service_id
    memory      = module.memory.service_id
    volume      = module.volume.service_id
    floating_ip = module.floating_ip.service_id
  }
}
