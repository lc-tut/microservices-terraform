variable "service_name" {
  type        = string
  description = "CloudKitty Hashmap の対象サービス名。collector の metrics.yml の alt_name と一致させる（例: vcpu, memory, volume, floating_ip）"
}

variable "field_name" {
  type        = string
  default     = null
  description = <<-EOT
    課金対象として使うメタデータのフィールド名（例: flavor_id, volume_type）。
    null なら service-level flat モード（var.service_rate を使う）。
  EOT
}

variable "mappings" {
  description = "field モード時: field_name の値ごとの単価設定。キーは field の実際の値（例: flavor 名）"
  type = map(object({
    cost = string # 数値だが JSON 送信の都合上 string で受ける
    type = string # "flat"（固定額）または "rate"（倍率）
  }))
  default = {}
}

variable "service_rate" {
  description = "service-level flat モード時（field_name == null）: service 直付けの単価"
  type = object({
    cost = string
    type = string # 通常 "flat"
  })
  default = null
}
