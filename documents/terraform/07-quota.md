# クォータ設計

## 概要

クォータ管理は OpenStack（VM・ストレージ・ネットワーク）と Kubernetes（コンテナリソース）の
2層で行います。どちらも共通のティアプリセットを使い、ティアを変えるだけで両層の上限が連動します。
プリセットの一部の値は `quota_override` / `k8s_quota_override` で個別上書きできます。

| 層 | 対象リソース | Terraform リソース |
|---|---|---|
| OpenStack | VM・ブロックストレージ・ネットワーク | Nova / Cinder / Neutron クォータ |
| Kubernetes | Pod・CPU・メモリ・PVC | ResourceQuota + LimitRange |

---

## クォータティアプリセット

ティア名は `lc-<type>` または `lc-<type>-<vcpu>` の形式です。
vCPU が基準で、メモリはデフォルト 2:1（`standard`）・4:1（`highmem`）・1:1（`highcpu`）比率です。

### OpenStack

#### Nova（コンピュート）

| ティア | instances | vCPU | RAM |
|---|---|---|---|
| `lc-micro` | 3 | 2 | 4 GB |
| `lc-small` | 5 | 4 | 8 GB |
| `lc-standard-8` | 8 | 8 | 16 GB |
| `lc-standard-16` | 12 | 16 | 32 GB |
| `lc-standard-32` | 20 | 32 | 64 GB |
| `lc-highmem-8` | 8 | 8 | 32 GB |
| `lc-highcpu-16` | 12 | 16 | 16 GB |

#### Cinder（ブロックストレージ）

| ティア | volumes | snapshots | gigabytes | per_volume_gigabytes |
|---|---|---|---|---|
| `lc-micro` | 5 | 5 | 50 GB | 50 GB |
| `lc-small` | 10 | 10 | 100 GB | 100 GB |
| `lc-standard-8` | 15 | 15 | 200 GB | 200 GB |
| `lc-standard-16` | 20 | 20 | 400 GB | 400 GB |
| `lc-standard-32` | 40 | 40 | 800 GB | 800 GB |
| `lc-highmem-8` | 20 | 20 | 300 GB | 300 GB |
| `lc-highcpu-16` | 15 | 15 | 200 GB | 200 GB |

> `per_volume_gigabytes` を `gigabytes` と同値に設定し、1 ボリュームへの独占を防ぎます。
> `backups`・`backup_gigabytes` はティアごとに固定値を設定しています（HCL 参照）。テーブルには記載しません。

#### Neutron（ネットワーク）

| ティア | network | subnet | port | router | floatingip | security_group | security_group_rule |
|---|---|---|---|---|---|---|---|
| `lc-micro` | 2 | 4 | 20 | 1 | 1 | 5 | 50 |
| `lc-small` | 3 | 6 | 40 | 2 | 2 | 10 | 100 |
| `lc-standard-8` | 5 | 10 | 80 | 3 | 3 | 15 | 150 |
| `lc-standard-16` | 8 | 16 | 150 | 5 | 5 | 25 | 250 |
| `lc-standard-32` | 12 | 24 | 250 | 8 | 10 | 40 | 400 |
| `lc-highmem-8` | 5 | 10 | 80 | 3 | 3 | 15 | 150 |
| `lc-highcpu-16` | 8 | 16 | 150 | 5 | 5 | 25 | 250 |

> `floatingip`（パブリック IP）は希少リソースです。外部公開は Ingress Controller 経由を推奨します。

---

### Kubernetes

Kubernetes クォータは OpenStack の vCPU / RAM に対応する値に揃えます。
`limits.cpu` / `limits.memory` が OpenStack の vCPU / RAM 上限と一致します。

#### ResourceQuota（Namespace 単位の上限）

| ティア | requests.cpu | limits.cpu | requests.memory | limits.memory | pods | services | PVC | requests.storage |
|---|---|---|---|---|---|---|---|---|
| `lc-micro` | 1 | 2 | 2Gi | 4Gi | 10 | 5 | 3 | 10Gi |
| `lc-small` | 2 | 4 | 4Gi | 8Gi | 20 | 10 | 5 | 20Gi |
| `lc-standard-8` | 4 | 8 | 8Gi | 16Gi | 30 | 15 | 8 | 40Gi |
| `lc-standard-16` | 8 | 16 | 16Gi | 32Gi | 60 | 25 | 12 | 80Gi |
| `lc-standard-32` | 16 | 32 | 32Gi | 64Gi | 120 | 50 | 20 | 150Gi |
| `lc-highmem-8` | 4 | 8 | 16Gi | 32Gi | 30 | 15 | 10 | 60Gi |
| `lc-highcpu-16` | 8 | 16 | 8Gi | 16Gi | 60 | 25 | 8 | 40Gi |

全ティアで `services.nodeports = 0`・`services.loadbalancers = 0` を強制します。
外部公開は共有 Ingress Controller（RKE2 ingress-nginx）経由のみ許可します。

> `requests.storage` は Kubernetes の PVC 専用ストレージ上限です。OpenStack の `gigabytes` は VM ルートディスク・データディスクも含むため値が大きく、両者の差は意図的です。

#### LimitRange（コンテナ単位のデフォルト・上限）

requests / limits を省略したコンテナに自動注入されるデフォルト値です。

| ティア | defaultRequest.cpu | defaultRequest.memory | default.cpu | default.memory | max.cpu | max.memory |
|---|---|---|---|---|---|---|
| `lc-micro` | 100m | 128Mi | 500m | 512Mi | 1 | 2Gi |
| `lc-small` | 100m | 128Mi | 500m | 512Mi | 2 | 4Gi |
| `lc-standard-8` | 100m | 256Mi | 500m | 1Gi | 4 | 8Gi |
| `lc-standard-16` | 200m | 256Mi | 1 | 2Gi | 8 | 16Gi |
| `lc-standard-32` | 200m | 512Mi | 1 | 4Gi | 16 | 32Gi |
| `lc-highmem-8` | 100m | 512Mi | 500m | 2Gi | 4 | 16Gi |
| `lc-highcpu-16` | 200m | 256Mi | 1 | 1Gi | 8 | 8Gi |

---

## 個別オーバーライド

プリセットを基準に一部の値だけ変えたい場合は `quota_override` / `k8s_quota_override` を使います。
省略したフィールドはプリセット値が使われます。

```hcl
# 例: lc-small ベースで floatingip だけ増やす
module "quota" {
  source     = "../../../../modules/lc-cloud-quota"
  project_id = lc_cloud_organization.this.openstack_project_id
  tier       = "lc-small"

  quota_override = {
    floatingip = 5
  }
}

# 例: lc-standard-8 ベースでメモリだけ増やす（highmem 相当）
module "namespace" {
  source     = "../../../modules/kubernetes-namespace"
  name       = var.project_name
  quota_tier = "lc-standard-8"

  k8s_quota_override = {
    limits_memory   = "32Gi"
    requests_memory = "16Gi"
  }
}
```

---

## Terraform モジュール

### `modules/lc-cloud-quota/`（OpenStack クォータ）

```hcl
# terraform/modules/lc-cloud-quota/main.tf
locals {
  tiers = {
    lc-micro = {
      instances = 3;  cores = 2;  ram = 4096
      volumes = 5;  snapshots = 5;  gigabytes = 50;  per_volume_gigabytes = 50
      backups = 3;  backup_gigabytes = 50
      network = 2;  subnet = 4;  port = 20;  router = 1
      floatingip = 1;  security_group = 5;  security_group_rule = 50
    }
    lc-small = {
      instances = 5;  cores = 4;  ram = 8192
      volumes = 10;  snapshots = 10;  gigabytes = 100;  per_volume_gigabytes = 100
      backups = 5;  backup_gigabytes = 100
      network = 3;  subnet = 6;  port = 40;  router = 2
      floatingip = 2;  security_group = 10;  security_group_rule = 100
    }
    lc-standard-8 = {
      instances = 8;  cores = 8;  ram = 16384
      volumes = 15;  snapshots = 15;  gigabytes = 200;  per_volume_gigabytes = 200
      backups = 8;  backup_gigabytes = 200
      network = 5;  subnet = 10;  port = 80;  router = 3
      floatingip = 3;  security_group = 15;  security_group_rule = 150
    }
    lc-standard-16 = {
      instances = 12;  cores = 16;  ram = 32768
      volumes = 20;  snapshots = 20;  gigabytes = 400;  per_volume_gigabytes = 400
      backups = 10;  backup_gigabytes = 400
      network = 8;  subnet = 16;  port = 150;  router = 5
      floatingip = 5;  security_group = 25;  security_group_rule = 250
    }
    lc-standard-32 = {
      instances = 20;  cores = 32;  ram = 65536
      volumes = 40;  snapshots = 40;  gigabytes = 800;  per_volume_gigabytes = 800
      backups = 20;  backup_gigabytes = 800
      network = 12;  subnet = 24;  port = 250;  router = 8
      floatingip = 10;  security_group = 40;  security_group_rule = 400
    }
    lc-highmem-8 = {
      instances = 8;  cores = 8;  ram = 32768
      volumes = 20;  snapshots = 20;  gigabytes = 300;  per_volume_gigabytes = 300
      backups = 10;  backup_gigabytes = 300
      network = 5;  subnet = 10;  port = 80;  router = 3
      floatingip = 3;  security_group = 15;  security_group_rule = 150
    }
    lc-highcpu-16 = {
      instances = 12;  cores = 16;  ram = 16384
      volumes = 15;  snapshots = 15;  gigabytes = 200;  per_volume_gigabytes = 200
      backups = 8;  backup_gigabytes = 200
      network = 8;  subnet = 16;  port = 150;  router = 5
      floatingip = 5;  security_group = 25;  security_group_rule = 250
    }
  }

  base = local.tiers[var.tier]
  q = {
    instances            = coalesce(var.quota_override.instances, local.base.instances)
    cores                = coalesce(var.quota_override.cores, local.base.cores)
    ram                  = var.quota_override.ram_gb != null ? var.quota_override.ram_gb * 1024 : local.base.ram
    volumes              = coalesce(var.quota_override.volumes, local.base.volumes)
    snapshots            = coalesce(var.quota_override.snapshots, local.base.snapshots)
    gigabytes            = coalesce(var.quota_override.gigabytes, local.base.gigabytes)
    per_volume_gigabytes = coalesce(var.quota_override.per_volume_gigabytes, local.base.per_volume_gigabytes)
    backups              = coalesce(var.quota_override.backups, local.base.backups)
    backup_gigabytes     = coalesce(var.quota_override.backup_gigabytes, local.base.backup_gigabytes)
    network              = coalesce(var.quota_override.network, local.base.network)
    subnet               = coalesce(var.quota_override.subnet, local.base.subnet)
    port                 = coalesce(var.quota_override.port, local.base.port)
    router               = coalesce(var.quota_override.router, local.base.router)
    floatingip           = coalesce(var.quota_override.floatingip, local.base.floatingip)
    security_group       = coalesce(var.quota_override.security_group, local.base.security_group)
    security_group_rule  = coalesce(var.quota_override.security_group_rule, local.base.security_group_rule)
  }
}

resource "openstack_compute_quotaset_v2" "this" {
  project_id           = var.project_id
  instances            = local.q.instances
  cores                = local.q.cores
  ram                  = local.q.ram
  # server_groups は「同時起動できる VM グループ数」≒ インスタンス数が自然な上限
  server_groups        = local.q.instances
  server_group_members = 5
  key_pairs            = 10
  metadata_items       = 128
}

resource "openstack_blockstorage_quotaset_v3" "this" {
  project_id           = var.project_id
  volumes              = local.q.volumes
  snapshots            = local.q.snapshots
  gigabytes            = local.q.gigabytes
  per_volume_gigabytes = local.q.per_volume_gigabytes
  backups              = local.q.backups
  backup_gigabytes     = local.q.backup_gigabytes
}

resource "openstack_networking_quota_v2" "this" {
  project_id          = var.project_id
  network             = local.q.network
  subnet              = local.q.subnet
  port                = local.q.port
  router              = local.q.router
  floatingip          = local.q.floatingip
  security_group      = local.q.security_group
  security_group_rule = local.q.security_group_rule
}
```

```hcl
# terraform/modules/lc-cloud-quota/variables.tf
variable "project_id" {
  type        = string
  description = "OpenStack（Keystone）プロジェクト UUID"
}

variable "tier" {
  type = string

  validation {
    condition = contains([
      "lc-micro", "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.tier)
    error_message = "有効なティア名を指定してください。"
  }
}

variable "quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します。"
  type = object({
    instances            = optional(number)
    cores                = optional(number)
    ram_gb               = optional(number)
    volumes              = optional(number)
    snapshots            = optional(number)
    gigabytes            = optional(number)
    per_volume_gigabytes = optional(number)
    backups              = optional(number)
    backup_gigabytes     = optional(number)
    network              = optional(number)
    subnet               = optional(number)
    port                 = optional(number)
    router               = optional(number)
    floatingip           = optional(number)
    security_group       = optional(number)
    security_group_rule  = optional(number)
  })
  default = {}
}
```

---

### `modules/kubernetes-namespace/`（Namespace + ResourceQuota + LimitRange + NetworkPolicy）

```hcl
# terraform/modules/kubernetes-namespace/main.tf
locals {
  tiers = {
    lc-micro = {
      req_cpu = "1";    lim_cpu = "2"
      req_mem = "2Gi";  lim_mem = "4Gi"
      pods = "10";  services = "5";  pvcs = "3";  storage = "10Gi"
      default_req_cpu = "100m";  default_req_mem = "128Mi"
      default_lim_cpu = "500m";  default_lim_mem = "512Mi"
      max_cpu = "1";  max_mem = "2Gi"
    }
    lc-small = {
      req_cpu = "2";    lim_cpu = "4"
      req_mem = "4Gi";  lim_mem = "8Gi"
      pods = "20";  services = "10";  pvcs = "5";  storage = "20Gi"
      default_req_cpu = "100m";  default_req_mem = "128Mi"
      default_lim_cpu = "500m";  default_lim_mem = "512Mi"
      max_cpu = "2";  max_mem = "4Gi"
    }
    lc-standard-8 = {
      req_cpu = "4";    lim_cpu = "8"
      req_mem = "8Gi";  lim_mem = "16Gi"
      pods = "30";  services = "15";  pvcs = "8";  storage = "40Gi"
      default_req_cpu = "100m";  default_req_mem = "256Mi"
      default_lim_cpu = "500m";  default_lim_mem = "1Gi"
      max_cpu = "4";  max_mem = "8Gi"
    }
    lc-standard-16 = {
      req_cpu = "8";    lim_cpu = "16"
      req_mem = "16Gi"; lim_mem = "32Gi"
      pods = "60";  services = "25";  pvcs = "12";  storage = "80Gi"
      default_req_cpu = "200m";  default_req_mem = "256Mi"
      default_lim_cpu = "1";     default_lim_mem = "2Gi"
      max_cpu = "8";  max_mem = "16Gi"
    }
    lc-standard-32 = {
      req_cpu = "16";   lim_cpu = "32"
      req_mem = "32Gi"; lim_mem = "64Gi"
      pods = "120";  services = "50";  pvcs = "20";  storage = "150Gi"
      default_req_cpu = "200m";  default_req_mem = "512Mi"
      default_lim_cpu = "1";     default_lim_mem = "4Gi"
      max_cpu = "16";  max_mem = "32Gi"
    }
    lc-highmem-8 = {
      req_cpu = "4";    lim_cpu = "8"
      req_mem = "16Gi"; lim_mem = "32Gi"
      pods = "30";  services = "15";  pvcs = "10";  storage = "60Gi"
      default_req_cpu = "100m";  default_req_mem = "512Mi"
      default_lim_cpu = "500m";  default_lim_mem = "2Gi"
      max_cpu = "4";  max_mem = "16Gi"
    }
    lc-highcpu-16 = {
      req_cpu = "8";    lim_cpu = "16"
      req_mem = "8Gi";  lim_mem = "16Gi"
      pods = "60";  services = "25";  pvcs = "8";  storage = "40Gi"
      default_req_cpu = "200m";  default_req_mem = "256Mi"
      default_lim_cpu = "1";     default_lim_mem = "1Gi"
      max_cpu = "8";  max_mem = "8Gi"
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

resource "kubernetes_namespace" "this" {
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

resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "default"
    namespace = kubernetes_namespace.this.metadata[0].name
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

resource "kubernetes_limit_range" "this" {
  metadata {
    name      = "default"
    namespace = kubernetes_namespace.this.metadata[0].name
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
```

```hcl
# terraform/modules/kubernetes-namespace/variables.tf
variable "name" {
  type = string
}

variable "quota_tier" {
  type    = string
  default = "lc-small"

  validation {
    condition = contains([
      "lc-micro", "lc-small",
      "lc-standard-8", "lc-standard-16", "lc-standard-32",
      "lc-highmem-8", "lc-highcpu-16"
    ], var.quota_tier)
    error_message = "有効なティア名を指定してください。"
  }
}

variable "k8s_quota_override" {
  description = "プリセットを上書きする個別値。省略したフィールドはプリセット値を使用します。"
  type = object({
    requests_cpu    = optional(string)
    limits_cpu      = optional(string)
    requests_memory = optional(string)
    limits_memory   = optional(string)
    pods            = optional(number)
    services        = optional(number)
    pvcs            = optional(number)
    storage         = optional(string)
  })
  default = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "allow_from_namespaces" {
  type        = list(string)
  description = "この Namespace へのアクセスを許可する追加 Namespace 名（例: monitoring）"
  default     = []
}

variable "ingress_controller_namespace" {
  type    = string
  default = "rke2-ingress-nginx"
}
```

```hcl
# terraform/modules/kubernetes-namespace/outputs.tf
output "namespace_name" {
  value = kubernetes_namespace.this.metadata[0].name
}

output "namespace_uid" {
  value = kubernetes_namespace.this.metadata[0].uid
}
```

---

## NetworkPolicy 設計

各 Namespace にデフォルトで以下の 4 ポリシーを適用します。
Egress は制限なし（デフォルト許可）で、必要に応じてプロジェクトが `workspaces/` で追加します。

| ポリシー | 内容 |
|---|---|
| `default-deny-ingress` | 全 Ingress をデフォルト拒否（ポリシー有効化の宣言） |
| `allow-same-namespace` | 同一 Namespace 内の Pod 間通信を許可 |
| `allow-from-kube-system` | DNS・ヘルスチェック・メトリクス収集を許可 |
| `allow-from-ingress` | RKE2 Ingress Controller からのアクセスを許可 |

複数の NetworkPolicy は OR（和集合）で評価されます。

```hcl
# terraform/modules/kubernetes-namespace/network_policy.tf
resource "kubernetes_network_policy" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from { pod_selector {} }
    }
  }
}

resource "kubernetes_network_policy" "allow_from_kube_system" {
  metadata {
    name      = "allow-from-kube-system"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_from_ingress" {
  metadata {
    name      = "allow-from-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.ingress_controller_namespace
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_from_extra" {
  count = length(var.allow_from_namespaces) > 0 ? 1 : 0

  metadata {
    name      = "allow-from-extra-namespaces"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    dynamic "ingress" {
      for_each = var.allow_from_namespaces
      content {
        from {
          namespace_selector {
            match_labels = { "kubernetes.io/metadata.name" = ingress.value }
          }
        }
      }
    }
  }
}
```

---

## platform/quotas/ の役割

`terraform/platform/quotas/` は **OpenStack グローバルデフォルト**（カスタマイズ未設定の全プロジェクトに適用される値）を管理します。
ティア定義はモジュール内に持ち、このスタックはデフォルト値の設定のみを担います。

```hcl
# terraform/platform/quotas/main.tf
# catalog/billing-accounts/ でカスタマイズしていない全プロジェクトに適用されるデフォルト値
# 個人デフォルト = lc-micro、チームデフォルト = lc-small に相当する値を設定する

resource "openstack_compute_quota_defaults_v2" "personal" {
  # lc-micro 相当
  instances = 3
  cores     = 2
  ram       = 4096
}

# Nova・Cinder・Neutron それぞれのデフォルト API で設定
# （OpenStack の quota-defaults エンドポイントを使用）
```

> 新しいティアの追加やティア値の変更は `modules/lc-cloud-quota/` と `modules/kubernetes-namespace/` の `locals.tiers` を直接編集してください。
