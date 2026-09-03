output "tier" {
  value       = var.tier
  description = "適用したティア名"
}

output "resolved_quota" {
  value       = local.q
  description = "オーバーライド適用後の実際のクォータ値"
}
