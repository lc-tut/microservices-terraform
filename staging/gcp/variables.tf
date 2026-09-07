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
  description = <<-EOT
    DevStack VM のブートディスク。DevStack のソース・Glance のイメージ・
    Cinder/Swift/Manila のループバック領域を含む。
    フル構成（Octavia の amphora イメージと Trove のゲストイメージを含む）で
    200GB を見ている。サービスを削るなら 150GB でも足りる。
  EOT
  type        = number
  default     = 200
}

# --- DevStack のサービス構成 ---
#
# 既定はフル構成。実機 Polaris の Service Catalog（2026-09-04 時点で
# cloudkitty / heat / placement / keystone / glance / neutron / cinder / nova）に
# 加えて、Phase 8・9 が待っている Designate と Octavia、13/12 が参照している
# Manila も入れている。staging で先に動かせれば、実機導入を待たずに
# catalog/ とモジュールの実装を進められる。
#
# **どれも stack.sh の所要時間と RAM を押し上げる。** 特に Octavia は
# amphora イメージを diskimage-builder で作るため、単体で 20〜30 分かかる。
# 使わないものは false にすること。

variable "enable_telemetry" {
  description = "Ceilometer + Gnocchi + CloudKitty。modules/cloudkitty-service と 09-costs.md の検証に要る"
  type        = bool
  default     = true
}

variable "enable_trove" {
  description = "Trove (DBaaS) + Barbican。modules/lc-db の検証に要る。ゲストイメージが約 1.4GB ある"
  type        = bool
  default     = true
}

variable "enable_heat" {
  description = "Heat (Orchestration)。実機 Polaris のカタログにも存在する"
  type        = bool
  default     = true
}

variable "enable_designate" {
  description = <<-EOT
    Designate (DNSaaS)。16-implementation-phases.md の Phase 8 が待っているもの。
    実機 Polaris には未導入だが、staging に入れておけば実装を先行できる。
    bind9 をバックエンドとして同居させる。
  EOT
  type        = bool
  default     = true
}

variable "enable_octavia" {
  description = <<-EOT
    Octavia (LBaaS)。Phase 9 が待っているもの。

    **stack.sh が最も長くなる原因。** amphora イメージを diskimage-builder で
    構築するため 20〜30 分余計にかかり、ディスクも数 GB 使う。さらに LB を1つ
    作るたびに amphora VM（1GB 前後）が起動する。
  EOT
  type        = bool
  default     = true
}

variable "enable_manila" {
  description = <<-EOT
    Manila (Shared File System)。12/13 が参照している。
    ドライバは LVM を使う（既定の generic ドライバはサービス VM を要求し、
    Trove・Octavia と合わせると 32GB では苦しいため）。
  EOT
  type        = bool
  default     = true
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

# --- メール ---
# 本番と同じメールサーバーを使う（招待・パスワードリセット・年次継続確認の
# 文面を staging で実際に確認するため）。
#
# **本物のメールが本物の宛先に届く。** platform/members を staging に向けて
# apply するときは send_enrollment_email = false にすること
# （staging/terraform/members.tfvars の既定）。

variable "smtp_host" {
  description = "Authentik のグローバルメール設定。空ならメールは送られない"
  type        = string
  default     = ""
}

variable "smtp_port" {
  type    = number
  default = 587
}

variable "smtp_username" {
  type    = string
  default = ""
}

variable "smtp_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "smtp_use_tls" {
  type    = bool
  default = true
}

variable "smtp_use_ssl" {
  type    = bool
  default = false
}

variable "smtp_from_address" {
  description = <<-EOT
    差出人アドレス。**本番と別の見分けがつく値にすること。**
    受け取った人が staging からのメールだと分かるようにしておくと、
    誤送信に気づける。
  EOT
  type        = string
  default     = ""
}

variable "authentik_version" {
  description = "Authentik のイメージタグ。local/authentik/docker-compose.yml と揃えること"
  type        = string
  default     = "2026.5.6"
}

# --- 公開設定 ---

variable "dns_zone" {
  description = <<-EOT
    staging を公開するドメイン。例 "staging.lcn.ad.jp"。
    ここから auth.<zone> / infra.<zone> / harbor.<zone> / openstack.<zone> を組み立てる。

    **apply したあと、terraform output の外部 IP に対して A レコードを自分で作ること。**
    Caddy は Let's Encrypt の HTTP-01 チャレンジで証明書を取るため、
    名前が IP を指していないと証明書が発行されない（Caddy は取れるまで再試行し続ける）。

    空文字にすると公開せず、到達経路は IAP トンネルだけになる。
  EOT
  type        = string
  default     = ""
}

variable "acme_email" {
  description = <<-EOT
    Let's Encrypt に登録する連絡先メールアドレス。
    証明書の期限切れ間近の通知が届く。dns_zone を設定するなら入れること。
  EOT
  type        = string
  default     = ""
}

variable "devstack_allowed_source_ranges" {
  description = <<-EOT
    DevStack（OpenStack API / Horizon, TCP 80）への接続を許可する送信元 CIDR。
    例 ["203.0.113.0/24"]。空なら公開せず IAP トンネル経由だけになる。

    **DevStack は平文 HTTP で公開される。** Keystone のトークン要求も
    Horizon のログインもこの経路を通るため、資格情報が経路上で読める。
    信頼できる回線の CIDR だけを入れること。恒久的に使うなら、
    DevStack も Caddy の裏に入れて TLS 終端する構成へ切り替えること。
  EOT
  type        = list(string)
  default     = []
}

variable "harbor_allowed_source_ranges" {
  description = <<-EOT
    Harbor（TCP 8080）への接続を許可する送信元 CIDR。空なら公開しない。
    dns_zone を設定している場合、Harbor は Caddy 経由の https://harbor.<zone> でも
    到達できるので、通常はここを空のままでよい。
  EOT
  type        = list(string)
  default     = []
}

variable "oidc_client_id" {
  description = <<-EOT
    Middleware API 用 OIDC クライアント ID。lcn-infra-api の
    LCN_OIDC_AUDIENCE と、Authentik 側 Provider の client_id の両方になる。
    terraform/platform/idp/ の middleware_oidc_client_id と同じ値にすること。
  EOT
  type        = string
  default     = "lcn-api"
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
    null（既定）なら、公開していなければ 45 分、公開していれば 0（無効）になる。

    **公開しているときにこれを有効にしてはいけない。** 判定材料が SSH の
    有無しかないため、ブラウザや API から使われている最中でも停止する。
    公開環境で稼働時間を絞りたい場合は daily_start_time / daily_stop_time を使うこと。
  EOT
  type        = number
  default     = null
}

variable "daily_start_time" {
  description = <<-EOT
    毎日この時刻に VM を起動する（"09:00" 形式、time_zone 基準）。
    空なら自動起動しない。停止だけ設定して手動で起こす運用でもよい。
  EOT
  type        = string
  default     = ""
}

variable "daily_stop_time" {
  description = <<-EOT
    毎日この時刻に VM を停止する（"23:00" 形式）。空なら自動停止しない。

    公開環境で費用を抑える手段はこちら。アクセスの有無を見ないので、
    使っている最中でも止まる。止まって困る時間帯を外して設定すること。
  EOT
  type        = string
  default     = ""
}

variable "schedule_time_zone" {
  description = "daily_start_time / daily_stop_time の時間帯（IANA 名）"
  type        = string
  default     = "Asia/Tokyo"
}
