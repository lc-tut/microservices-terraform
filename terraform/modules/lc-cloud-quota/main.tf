locals {
  tiers = {
    lc-micro = {
      instances            = 3
      cores                = 2
      ram                  = 4096
      volumes              = 5
      snapshots            = 5
      gigabytes            = 50
      per_volume_gigabytes = 50
      backups              = 3
      backup_gigabytes     = 50
      network              = 2
      subnet               = 4
      port                 = 20
      router               = 1
      floatingip           = 1
      security_group       = 5
      security_group_rule  = 50
    }
    lc-small = {
      instances            = 5
      cores                = 4
      ram                  = 8192
      volumes              = 10
      snapshots            = 10
      gigabytes            = 100
      per_volume_gigabytes = 100
      backups              = 5
      backup_gigabytes     = 100
      network              = 3
      subnet               = 6
      port                 = 40
      router               = 2
      floatingip           = 2
      security_group       = 10
      security_group_rule  = 100
    }
    lc-standard-8 = {
      instances            = 8
      cores                = 8
      ram                  = 16384
      volumes              = 15
      snapshots            = 15
      gigabytes            = 200
      per_volume_gigabytes = 200
      backups              = 8
      backup_gigabytes     = 200
      network              = 5
      subnet               = 10
      port                 = 80
      router               = 3
      floatingip           = 3
      security_group       = 15
      security_group_rule  = 150
    }
    lc-standard-16 = {
      instances            = 12
      cores                = 16
      ram                  = 32768
      volumes              = 20
      snapshots            = 20
      gigabytes            = 400
      per_volume_gigabytes = 400
      backups              = 10
      backup_gigabytes     = 400
      network              = 8
      subnet               = 16
      port                 = 150
      router               = 5
      floatingip           = 5
      security_group       = 25
      security_group_rule  = 250
    }
    lc-standard-32 = {
      instances            = 20
      cores                = 32
      ram                  = 65536
      volumes              = 40
      snapshots            = 40
      gigabytes            = 800
      per_volume_gigabytes = 800
      backups              = 20
      backup_gigabytes     = 800
      network              = 12
      subnet               = 24
      port                 = 250
      router               = 8
      floatingip           = 10
      security_group       = 40
      security_group_rule  = 400
    }
    lc-highmem-8 = {
      instances            = 8
      cores                = 8
      ram                  = 32768
      volumes              = 20
      snapshots            = 20
      gigabytes            = 300
      per_volume_gigabytes = 300
      backups              = 10
      backup_gigabytes     = 300
      network              = 5
      subnet               = 10
      port                 = 80
      router               = 3
      floatingip           = 3
      security_group       = 15
      security_group_rule  = 150
    }
    lc-highcpu-16 = {
      instances            = 12
      cores                = 16
      ram                  = 16384
      volumes              = 15
      snapshots            = 15
      gigabytes            = 200
      per_volume_gigabytes = 200
      backups              = 8
      backup_gigabytes     = 200
      network              = 8
      subnet               = 16
      port                 = 150
      router               = 5
      floatingip           = 5
      security_group       = 25
      security_group_rule  = 250
    }
  }

  base = local.tiers[var.tier]
  q = {
    instances            = coalesce(var.quota_override.instances, local.base.instances)
    cores                = coalesce(var.quota_override.cores, local.base.cores)
    ram                  = var.quota_override.ram_gb != null ? var.quota_override.ram_gb * 1024 : local.base.ram
    volumes              = coalesce(var.quota_override.volumes, local.base.volumes)
    snapshots            = coalesce(var.quota_override.snapshots, local.base.snapshots)
    gigabytes            = coalesce(var.quota_override.gigabytes, local.base.gigabytes)
    per_volume_gigabytes = coalesce(var.quota_override.per_volume_gigabytes, local.base.per_volume_gigabytes)
    backups              = coalesce(var.quota_override.backups, local.base.backups)
    backup_gigabytes     = coalesce(var.quota_override.backup_gigabytes, local.base.backup_gigabytes)
    network              = coalesce(var.quota_override.network, local.base.network)
    subnet               = coalesce(var.quota_override.subnet, local.base.subnet)
    port                 = coalesce(var.quota_override.port, local.base.port)
    router               = coalesce(var.quota_override.router, local.base.router)
    floatingip           = coalesce(var.quota_override.floatingip, local.base.floatingip)
    security_group       = coalesce(var.quota_override.security_group, local.base.security_group)
    security_group_rule  = coalesce(var.quota_override.security_group_rule, local.base.security_group_rule)
  }
}

resource "openstack_compute_quotaset_v2" "this" {
  project_id = var.project_id
  instances  = local.q.instances
  cores      = local.q.cores
  ram        = local.q.ram
  # server_groups は「同時起動できる VM グループ数」≒ インスタンス数が自然な上限
  server_groups        = local.q.instances
  server_group_members = 5
  key_pairs            = 10
  metadata_items       = 128
}

resource "openstack_blockstorage_quotaset_v3" "this" {
  project_id           = var.project_id
  volumes              = local.q.volumes
  snapshots            = local.q.snapshots
  gigabytes            = local.q.gigabytes
  per_volume_gigabytes = local.q.per_volume_gigabytes
  backups              = local.q.backups
  backup_gigabytes     = local.q.backup_gigabytes
}

resource "openstack_networking_quota_v2" "this" {
  project_id          = var.project_id
  network             = local.q.network
  subnet              = local.q.subnet
  port                = local.q.port
  router              = local.q.router
  floatingip          = local.q.floatingip
  security_group      = local.q.security_group
  security_group_rule = local.q.security_group_rule
}
