locals {
  tiers = {
    lc-micro = {
      req_cpu         = "1"
      lim_cpu         = "2"
      req_mem         = "2Gi"
      lim_mem         = "4Gi"
      pods            = "10"
      services        = "5"
      pvcs            = "3"
      storage         = "10Gi"
      default_req_cpu = "100m"
      default_req_mem = "128Mi"
      default_lim_cpu = "500m"
      default_lim_mem = "512Mi"
      max_cpu         = "1"
      max_mem         = "2Gi"
    }
    lc-small = {
      req_cpu         = "2"
      lim_cpu         = "4"
      req_mem         = "4Gi"
      lim_mem         = "8Gi"
      pods            = "20"
      services        = "10"
      pvcs            = "5"
      storage         = "20Gi"
      default_req_cpu = "100m"
      default_req_mem = "128Mi"
      default_lim_cpu = "500m"
      default_lim_mem = "512Mi"
      max_cpu         = "2"
      max_mem         = "4Gi"
    }
    lc-standard-8 = {
      req_cpu         = "4"
      lim_cpu         = "8"
      req_mem         = "8Gi"
      lim_mem         = "16Gi"
      pods            = "30"
      services        = "15"
      pvcs            = "8"
      storage         = "40Gi"
      default_req_cpu = "100m"
      default_req_mem = "256Mi"
      default_lim_cpu = "500m"
      default_lim_mem = "1Gi"
      max_cpu         = "4"
      max_mem         = "8Gi"
    }
    lc-standard-16 = {
      req_cpu         = "8"
      lim_cpu         = "16"
      req_mem         = "16Gi"
      lim_mem         = "32Gi"
      pods            = "60"
      services        = "25"
      pvcs            = "12"
      storage         = "80Gi"
      default_req_cpu = "200m"
      default_req_mem = "256Mi"
      default_lim_cpu = "1"
      default_lim_mem = "2Gi"
      max_cpu         = "8"
      max_mem         = "16Gi"
    }
    lc-standard-32 = {
      req_cpu         = "16"
      lim_cpu         = "32"
      req_mem         = "32Gi"
      lim_mem         = "64Gi"
      pods            = "120"
      services        = "50"
      pvcs            = "20"
      storage         = "150Gi"
      default_req_cpu = "200m"
      default_req_mem = "512Mi"
      default_lim_cpu = "1"
      default_lim_mem = "4Gi"
      max_cpu         = "16"
      max_mem         = "32Gi"
    }
    lc-highmem-8 = {
      req_cpu         = "4"
      lim_cpu         = "8"
      req_mem         = "16Gi"
      lim_mem         = "32Gi"
      pods            = "30"
      services        = "15"
      pvcs            = "10"
      storage         = "60Gi"
      default_req_cpu = "100m"
      default_req_mem = "512Mi"
      default_lim_cpu = "500m"
      default_lim_mem = "2Gi"
      max_cpu         = "4"
      max_mem         = "16Gi"
    }
    lc-highcpu-16 = {
      req_cpu         = "8"
      lim_cpu         = "16"
      req_mem         = "8Gi"
      lim_mem         = "16Gi"
      pods            = "60"
      services        = "25"
      pvcs            = "8"
      storage         = "40Gi"
      default_req_cpu = "200m"
      default_req_mem = "256Mi"
      default_lim_cpu = "1"
      default_lim_mem = "1Gi"
      max_cpu         = "8"
      max_mem         = "8Gi"
    }
  }

  base = local.tiers[var.quota_tier]
  t = {
    req_cpu         = coalesce(var.k8s_quota_override.requests_cpu, local.base.req_cpu)
    lim_cpu         = coalesce(var.k8s_quota_override.limits_cpu, local.base.lim_cpu)
    req_mem         = coalesce(var.k8s_quota_override.requests_memory, local.base.req_mem)
    lim_mem         = coalesce(var.k8s_quota_override.limits_memory, local.base.lim_mem)
    pods            = coalesce(var.k8s_quota_override.pods != null ? tostring(var.k8s_quota_override.pods) : null, local.base.pods)
    services        = coalesce(var.k8s_quota_override.services != null ? tostring(var.k8s_quota_override.services) : null, local.base.services)
    pvcs            = coalesce(var.k8s_quota_override.pvcs != null ? tostring(var.k8s_quota_override.pvcs) : null, local.base.pvcs)
    storage         = coalesce(var.k8s_quota_override.storage, local.base.storage)
    default_req_cpu = local.base.default_req_cpu
    default_req_mem = local.base.default_req_mem
    default_lim_cpu = local.base.default_lim_cpu
    default_lim_mem = local.base.default_lim_mem
    max_cpu         = local.base.max_cpu
    max_mem         = local.base.max_mem
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.name
    labels = merge(
      {
        "lc-cloud/quota-tier" = var.quota_tier
        "lc-cloud/managed-by" = "terraform"
      },
      var.labels
    )
  }
}

resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "default"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"           = local.t.req_cpu
      "limits.cpu"             = local.t.lim_cpu
      "requests.memory"        = local.t.req_mem
      "limits.memory"          = local.t.lim_mem
      "pods"                   = local.t.pods
      "services"               = local.t.services
      "persistentvolumeclaims" = local.t.pvcs
      "requests.storage"       = local.t.storage
      "services.nodeports"     = "0"
      "services.loadbalancers" = "0"
    }
  }
}

resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "default"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = local.t.default_req_cpu
        memory = local.t.default_req_mem
      }
      default = {
        cpu    = local.t.default_lim_cpu
        memory = local.t.default_lim_mem
      }
      max = {
        cpu    = local.t.max_cpu
        memory = local.t.max_mem
      }
      min = {
        cpu    = "10m"
        memory = "32Mi"
      }
    }
  }
}
