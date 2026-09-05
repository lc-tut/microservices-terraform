variable "namespace" {
  type        = string
  description = "所属する Namespace名。modules/kubernetes-namespace が作成済みのものを data source で自動解決する"
}

variable "name" {
  type        = string
  description = "アプリ名。作成する PVC/Secret/ConfigMap 名のプレフィックスに使う"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "全リソース共通で付与する追加ラベル"
}

variable "persistent_volume_claims" {
  description = <<-EOT
    キーをサフィックスとして `$${var.name}-<key>` の名前で PVC を作成する。
    例: { "data" = { storage = "10Gi" } } → PVC 名 "myapp-data"
  EOT
  type = map(object({
    storage_class_name = optional(string)
    access_modes       = optional(list(string), ["ReadWriteOnce"])
    storage            = string
  }))
  default = {}
}

variable "secrets" {
  description = <<-EOT
    キーをサフィックスとして `$${var.name}-<key>` の名前で Secret を作成する。
    `data` は値そのもの（base64エンコード不要、provider側で行う）。
    provider の `kubernetes_secret_v1.data` 自体が sensitive 属性のため
    plan/apply 出力では隠れるが、state には平文で残る点に注意
    （SOPS 等で暗号化した値を variable 経由で渡す運用を想定）。
  EOT
  type = map(object({
    type = optional(string, "Opaque")
    data = optional(map(string), {})
  }))
  default = {}
}

variable "config_maps" {
  description = <<-EOT
    キーをサフィックスとして `$${var.name}-<key>` の名前で ConfigMap を作成する。
    例: { "config" = { data = { "app.conf" = "..." } } } → ConfigMap 名 "myapp-config"
  EOT
  type = map(object({
    data = optional(map(string), {})
  }))
  default = {}
}
