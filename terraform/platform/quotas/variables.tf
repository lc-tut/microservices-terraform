variable "openstack_admin_project_id" {
  type        = string
  description = <<-EOT
    Cinder の os-quota-class-sets API は URL パスに project_id を要求する
    （操作対象は project_id に関係なく常に "default" クラスだが、API の
    パス構造上必要）。admin 権限で認証しているプロジェクトの ID を渡す。
  EOT
}
