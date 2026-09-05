# network は catalog/projects/<project_name>/ が作成済みのものを参照する
# (modules/lc-vm と同じ自動解決パターン)。
data "openstack_networking_network_v2" "project" {
  name = var.project_name
}

# Trove flavor 一覧が Nova flavor と一致する環境向けの名前解決。
# 一致しない環境では var.flavor_id を直接渡す(variables.tf 参照)。
data "openstack_compute_flavor_v2" "this" {
  count = var.flavor_id == null ? 1 : 0
  name  = var.flavor
}

locals {
  flavor_id = var.flavor_id != null ? var.flavor_id : data.openstack_compute_flavor_v2.this[0].id
}

resource "openstack_db_instance_v1" "this" {
  name      = var.name
  flavor_id = local.flavor_id
  size      = var.volume_size_gb

  volume_type      = var.volume_type
  configuration_id = var.configuration_id

  datastore {
    type    = var.datastore_type
    version = var.datastore_version
  }

  network {
    uuid = data.openstack_networking_network_v2.project.id
  }

  # database/user はインスタンス本体と切り離して独立リソース化する
  # (modules/lc-vm が volume を独立リソース化しているのと同じ理由。
  # openstack_db_instance_v1 の inline database/user block は変更のたびに
  # インスタンス再作成を要求するが、openstack_db_database_v1 /
  # openstack_db_user_v1 は単体で追加・削除できる)。
}

resource "openstack_db_database_v1" "this" {
  for_each = { for db in var.databases : db.name => db }

  name        = each.value.name
  instance_id = openstack_db_instance_v1.this.id
}

resource "openstack_db_user_v1" "this" {
  for_each = var.users

  name        = each.key
  instance_id = openstack_db_instance_v1.this.id
  password    = each.value.password
  databases   = each.value.databases

  depends_on = [openstack_db_database_v1.this]
}
