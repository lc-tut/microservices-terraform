variable "os_cloud" {
  type        = string
  description = "local/clouds.yaml の cloud 名（idp-infra 等と同じプロジェクトにスコープされていること）"
  default     = "polaris-admin"
}

variable "instance_name" {
  type    = string
  default = "harbor"
}

variable "image_name" {
  type        = string
  description = "ベース OS イメージ名（環境に登録済みのもの）"
  default     = "rocky-10"
}

variable "flavor_name" {
  type        = string
  description = "Harbor 一式（core/jobservice/registry/portal/redis/postgresql/trivy）を Docker Compose で動かす最小現実解"
  default     = "m1.medium"
}

variable "root_volume_size" {
  type        = number
  description = "ルートボリューム GB。レジストリに push されるイメージ本体を溜め込む前提で余裕を見て 40"
  default     = 40
}

variable "private_network_name" {
  type    = string
  default = "lc-dev-net"
}

variable "external_network_name" {
  type        = string
  description = "Floating IP を払い出す外部ネットワーク"
  default     = "ext-net"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "SSH(22) を許可する送信元 CIDR"
  default     = "0.0.0.0/0"
}

variable "harbor_allowed_cidr" {
  type        = string
  description = "Harbor portal/registry(80) を許可する送信元 CIDR"
  default     = "0.0.0.0/0"
}

variable "harbor_hostname" {
  type        = string
  description = <<-EOT
    Harbor の harbor.yml `hostname`。docker login/push/pull 時にクライアントが
    指定するホスト名で、レジストリの内部参照にも使われる。この VM の Floating IP
    は apply するまで確定しないため既定値を置かない。初回 apply 後に
    `terraform output floating_ip` で判明したアドレスを渡して再 apply するか、
    あらかじめ確保済みの Floating IP / DNS 名があればそれを渡す
    （README「デプロイ」参照）。
  EOT
}

variable "harbor_version" {
  type        = string
  description = "Harbor online installer のバージョン（GitHub Releases のタグ）"
  default     = "v2.13.1"
}

variable "harbor_with_trivy" {
  type        = bool
  description = "trivy（脆弱性スキャナ）を同梱するか"
  default     = true
}
