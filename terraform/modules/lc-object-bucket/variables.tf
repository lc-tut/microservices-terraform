variable "name" {
  type        = string
  description = "コンテナ名。同一プロジェクト内で一意にすること"
}

variable "region" {
  type        = string
  default     = null
  description = "作成先リージョン。null なら provider のデフォルトを使う。output の container_url を絞り込む際にも使う"
}

variable "public_read" {
  type        = bool
  default     = false
  description = "true の場合、container_read が未指定なら \".r:*\"（誰でも GET 可能）を設定する簡易フラグ"
}

variable "container_read" {
  type        = string
  default     = null
  description = "Swift ACL（読み取り）を直接指定する場合に使う。指定時は public_read より優先される"
}

variable "container_write" {
  type        = string
  default     = null
  description = "Swift ACL（書き込み）。例: \"<project_id>:<username>\""
}

variable "versioning" {
  type        = bool
  default     = false
  description = "オブジェクトバージョニングを有効化するか（Swift 2.24+ かつ cloud 管理者が allow_object_versioning=true にしている必要あり）"
}

variable "storage_policy" {
  type        = string
  default     = null
  description = "Swift storage policy名"
}

variable "storage_class" {
  type        = string
  default     = null
  description = "Ceph RGW Swift API 実装でのみ有効なストレージクラス"
}

variable "content_type" {
  type        = string
  default     = null
  description = "コンテナ自体の MIME type"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "true の場合、destroy 時にコンテナ内オブジェクトを全削除してから削除する（復元不可）"
}

variable "cors" {
  description = <<-EOT
    CORS設定。`X-Container-Meta-Access-Control-*` として metadata に反映される
    (https://docs.openstack.org/swift/latest/cors.html)。
    未指定（null）なら CORS 関連ヘッダーは一切設定しない。
  EOT
  type = object({
    allow_origin   = optional(list(string))
    max_age        = optional(number)
    expose_headers = optional(list(string))
  })
  default = null
}

variable "metadata" {
  type        = map(string)
  default     = {}
  description = "追加のコンテナメタデータ（\"X-Container-Meta-<Key>\" として設定される）。cors と同じキーを指定した場合は cors の設定値が優先される"
}
