output "instance_name" {
  description = "VM インスタンス名（gcloud compute instances start/stop に使う）"
  value       = google_compute_instance.devstack.name
}

output "project_id" {
  value = var.project_id
}

output "zone" {
  description = "VM のゾーン（gcloud compute コマンドに使う）"
  value       = var.zone
}

output "external_ip" {
  description = "静的外部 IP。IAP トンネルは張らずこの IP を直接ブラウザで開くことはできない（ファイアウォールが IAP レンジのみ許可のため）"
  value       = google_compute_address.devstack.address
}
