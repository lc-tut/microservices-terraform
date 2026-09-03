output "namespace_name" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "namespace_uid" {
  value = kubernetes_namespace_v1.this.metadata[0].uid
}
