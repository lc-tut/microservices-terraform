# Namespace は workspaces/ 側が modules/kubernetes-namespace で作成済みのものを
# 参照するだけ（本モジュールでは作らない）。data source で存在確認しつつ、
# 実際の名前解決も string 直渡しではなくこちらを経由する
# (12-openstack-resources.md「Namespace は data で自動参照」)。
data "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_persistent_volume_claim_v1" "this" {
  for_each = var.persistent_volume_claims

  metadata {
    name      = "${var.name}-${each.key}"
    namespace = data.kubernetes_namespace_v1.this.metadata[0].name
    labels    = var.labels
  }

  spec {
    access_modes       = each.value.access_modes
    storage_class_name = each.value.storage_class_name

    resources {
      requests = {
        storage = each.value.storage
      }
    }
  }

  # storage_class_name 未指定時にクラスターのデフォルトが補完されるなど、
  # Provisioner 側の挙動で外部から差分が入るのを避ける
  # (workspaces/ からの明示的な変更は引き続き diff に出る)。
  wait_until_bound = false
}

resource "kubernetes_secret_v1" "this" {
  for_each = var.secrets

  metadata {
    name      = "${var.name}-${each.key}"
    namespace = data.kubernetes_namespace_v1.this.metadata[0].name
    labels    = var.labels
  }

  type = each.value.type
  data = each.value.data
}

resource "kubernetes_config_map_v1" "this" {
  for_each = var.config_maps

  metadata {
    name      = "${var.name}-${each.key}"
    namespace = data.kubernetes_namespace_v1.this.metadata[0].name
    labels    = var.labels
  }

  data = each.value.data
}
