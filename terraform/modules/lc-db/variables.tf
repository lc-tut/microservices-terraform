variable "name" {
  type        = string
  description = "DBインスタンス名。同一プロジェクト内で一意にすること"
}

variable "project_name" {
  type        = string
  description = "所属する catalog/projects の名前。同名の network を data source で自動解決する"
}

variable "flavor" {
  type        = string
  default     = null
  description = <<-EOT
    Nova flavor名（例: m1.medium）。data source で flavor_id を自動解決する。
    Trove の flavor 一覧が Nova flavor と一致しない環境では `flavor_id` を
    直接指定すること（その場合こちらは無視される）。
  EOT
}

variable "flavor_id" {
  type        = string
  default     = null
  description = "Trove flavor ID を直接指定する場合に使う（`var.flavor` による自動解決より優先）"
}

variable "volume_size_gb" {
  type        = number
  description = "DBインスタンスのボリュームサイズ(GB)"
}

variable "volume_type" {
  type        = string
  default     = null
  description = "Cinder volume type。null ならバックエンドのデフォルトを使う"
}

variable "datastore_type" {
  type        = string
  default     = "mysql"
  description = "Trove datastore種別。実機で trove-manage datastore_update 済みのものを指定する(documents/terraform/17-production-runbook.md Phase 5-5 参照)"
}

variable "datastore_version" {
  type        = string
  description = "Trove datastore バージョン。実機で trove-manage datastore_version_update 済みのものを指定する"
}

variable "configuration_id" {
  type        = string
  default     = null
  description = "アタッチする Trove configuration group の ID（省略可）"
}

variable "databases" {
  type = list(object({
    name    = string
    charset = optional(string)
    collate = optional(string)
  }))
  default     = []
  description = "作成するデータベースの一覧"
}

variable "users" {
  description = <<-EOT
    作成するユーザーの一覧。キーがユーザー名。
    provider の仕様上 password を含め state に平文で残る点に注意
    （openstack_db_user_v1 のドキュメント参照）。
    `openstack_db_user_v1` に host 引数は無い(全ホストからの接続を許可する
    Trove デフォルト動作のまま)。
  EOT
  type = map(object({
    password  = string
    databases = optional(list(string), [])
  }))
  default = {}
}
