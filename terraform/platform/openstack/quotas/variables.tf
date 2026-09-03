variable "openstack_admin_project_id" {
  type        = string
  default     = null
  description = <<-EOT
    未使用（実機確認の結果、この Cinder デプロイでは project-id を URL に
    含めるとむしろ 400 エラーになるため。main.tf のコメント参照）。
    project-id 必須の古い Cinder API バージョンに対応する必要が生じた場合の
    ために変数だけ残してある。
  EOT
}
