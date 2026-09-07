variable "project_id" {
  description = "GCP プロジェクト ID（既存の local/gcp-devstack と同じ main-vcompute を想定）"
  type        = string
}

variable "region" {
  description = "リソースを作成するリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "VM を作成するゾーン"
  type        = string
  default     = "asia-northeast1-a"
}

variable "name_prefix" {
  description = "リソース名の接頭辞。local/gcp-devstack の devstack-harbor と衝突させないためのもの"
  type        = string
  default     = "lc-staging"
}

variable "subnet_cidr" {
  description = <<-EOT
    staging 専用 VPC のサブネット。local/gcp-devstack は 10.10.0.0/24 を使うため
    重ならない範囲にしている。VPC が分かれているので技術的には重なっても動くが、
    将来ピアリングする可能性と、ログを見たときにどちらの環境か判別できることを優先する。
  EOT
  type        = string
  default     = "10.20.0.0/24"
}

variable "devstack_internal_ip" {
  description = <<-EOT
    DevStack VM の内部 IP を固定する。DevStack は HOST_IP を各サービスの
    設定ファイルと Keystone のサービスカタログに焼き込むため、IP が変わると
    「一見動いているが一部が古い IP を向いている」状態になる。
    platform VM 側の設定（OS_AUTH_URL）もこの IP を直接参照する。
  EOT
  type        = string
  default     = "10.20.0.10"
}

variable "platform_internal_ip" {
  description = "platform VM の内部 IP。Harbor の hostname と Authentik の外部 URL に焼き込むため固定する"
  type        = string
  default     = "10.20.0.11"
}

# --- DevStack VM ---

variable "devstack_machine_type" {
  description = <<-EOT
    DevStack VM のマシンタイプ。
    DevStack で先に詰まるのは CPU ではなく RAM（Nova のゲスト VM に加えて
    Trove・CloudKitty・Gnocchi が常駐する）。そのため vCPU は local と同じ 4 のまま
    メモリだけ倍にした n2-highmem-4 を既定にしている。
    E2 系はネステッド仮想化に非対応で /dev/kvm が使えないため選べない。
  EOT
  type        = string
  default     = "n2-highmem-4"
}

variable "devstack_boot_disk_size_gb" {
  description = "DevStack VM のブートディスク（DevStack のソース・イメージ・Cinder/Swift のループバック領域を含む）"
  type        = number
  default     = 150
}

variable "devstack_admin_password" {
  description = "DevStack の admin / service パスワード（Keystone admin, DB, RabbitMQ 共通）"
  type        = string
  sensitive   = true
}

variable "enable_nested_virtualization" {
  description = <<-EOT
    ネステッド仮想化。DevStack の Nova が建てる VM を KVM で動かすために必要。
    false にすると virt_type=qemu になり、cirros 程度しか起動しきらない。
  EOT
  type        = bool
  default     = true
}

# --- platform VM ---

variable "platform_machine_type" {
  description = <<-EOT
    platform VM（k3s + Authentik + Harbor + Middleware API）のマシンタイプ。
    ネステッド仮想化が不要なので、同スペックで約3割安い E2 系を既定にする。
    内訳の見積もりは k3s 0.5GB / Authentik(server+worker+postgres) 2.5GB /
    Harbor 2.5GB / Outpost + ingress-nginx 0.3GB / infra-api 一式 0.5GB。
  EOT
  type        = string
  default     = "e2-standard-4"
}

variable "platform_boot_disk_size_gb" {
  description = "platform VM のブートディスク（Harbor のイメージ領域と k3s の local-path PV を含む）"
  type        = number
  default     = 50
}

variable "enable_harbor" {
  description = <<-EOT
    platform VM に Harbor を入れるか。terraform/platform/harbor/ の動作確認に使う。
    要らなければ false にすると bootstrap が約10分短くなり、RAM も 2.5GB 空く。
  EOT
  type        = bool
  default     = true
}

variable "harbor_version" {
  description = "Harbor のバージョン（オンラインインストーラのタグ）"
  type        = string
  default     = "v2.15.2"
}

variable "harbor_admin_password" {
  description = "Harbor admin ユーザーのパスワード"
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_secret_key" {
  description = "Authentik の AUTHENTIK_SECRET_KEY。空なら Terraform が生成して state に持つ"
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_bootstrap_password" {
  description = "Authentik の akadmin 初期パスワード。空なら Terraform が生成する"
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_bootstrap_token" {
  description = <<-EOT
    Authentik の akadmin API トークン。terraform/platform/idp/ を staging に向けて
    apply するときの AUTHENTIK_TOKEN になる。空なら Terraform が生成する。
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_version" {
  description = "Authentik のイメージタグ。local/authentik/docker-compose.yml と揃えること"
  type        = string
  default     = "2026.5.6"
}

# --- 運用 ---

variable "iap_tunnel_users" {
  description = "IAP トンネル (roles/iap.tunnelResourceAccessor) を許可するユーザー（\"user:you@example.com\" 形式）"
  type        = list(string)
  default     = []
}

variable "idle_shutdown_minutes" {
  description = <<-EOT
    SSH（= IAP トンネル）が何分途切れたら VM を自動停止するか。0 で無効。
    staging へのアクセスは全て IAP トンネル越しなので、トンネルが無い＝誰も使って
    いない、と判断できる。stack.sh 実行中と /run/no-idle-shutdown がある間は停止しない。
  EOT
  type        = number
  default     = 45
}
