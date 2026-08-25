# デフォルトブランドに recovery flow を設定する
# これにより POST /api/v3/core/users/{id}/recovery/ がメールを送信できる
data "authentik_brand" "default" {
  domain = "authentik-default"
}

locals {
  # branding_logo/branding_favicon/branding_default_flow_background は、Authentik
  # 2025.12+ の File picker が外部URL（http(s)://...）をパススルー値として正式
  # サポートしているため（文字種バリデーションはローカルアップロードパス用で、
  # 外部URLはスキップされる。authentik/admin/files/backends/passthrough.py 参照）、
  # Terraform からアップロードせずに assets/ 配下の画像を raw.githubusercontent.com
  # 経由でそのまま参照できる。このリポジトリは public のため、main に push 済みで
  # あれば誰でも読める。未pushの状態だと 404 になる点に注意。
  idp_assets_base_url = "https://raw.githubusercontent.com/lc-tut/microservices-terraform/main/terraform/platform/idp/assets"
}

resource "authentik_brand" "default" {
  domain        = data.authentik_brand.default.domain
  default       = true
  flow_recovery = authentik_flow.recovery.uuid

  branding_title   = "LinuxClub"
  branding_logo    = "${local.idp_assets_base_url}/linuxclub_wide_logo.png"
  branding_favicon = "${local.idp_assets_base_url}/logo.png"

  # 個別 flow (enrollment/recovery/annual_renewal) は background を明示していないため、
  # ここがすべての flow 実行画面のデフォルト背景として使われる
  # （authentik/flows/models.py Flow.background_url: flow.background が未設定なら
  # brand.branding_default_flow_background にフォールバックする）
  branding_default_flow_background = "${local.idp_assets_base_url}/linuxclub_flow_background.jpg"
}
