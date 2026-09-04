# network/subnet は admin 権限で作成しつつ tenant_id を明示することで、
# チームプロジェクト所有のリソースにする（Neutron は admin による代理作成を許可する）。
resource "openstack_networking_network_v2" "project" {
  name      = var.project_name
  tenant_id = var.team_project_id
}

resource "openstack_networking_subnet_v2" "project" {
  name          = var.project_name
  network_id    = openstack_networking_network_v2.project.id
  tenant_id     = var.team_project_id
  subnetpool_id = var.subnetpool_id
  ip_version    = 4
}

resource "openstack_networking_router_interface_v2" "project" {
  router_id = var.vpc_gateway_router_id
  subnet_id = openstack_networking_subnet_v2.project.id
}

# openstack_identity_application_credential_v3 はセルフサービス限定のため
# team_scoped provider（team_project_id にスコープしなおしたもの）で作る。
#
# access_rules の service には実機 Polaris の Service Catalog の type を使う
# （`openstack catalog list` で確認: nova=compute, cinder=block-storage,
# neutron=network, glance=image）。Designate（dns）・Octavia（load-balancer）は
# 実機に未導入のため含めていない（16-implementation-phases.md の Phase 8・9）。
# Swift（object-store）も実機カタログに無いが、環境が追いつけば使える想定で
# ルールだけ先に含めている（無害。使われるまでは単に一致するエンドポイントが無いだけ）。
# 詳細は 12-openstack-resources.md「Access Rules 仕様」参照。
resource "openstack_identity_application_credential_v3" "workspace_ci" {
  provider    = openstack.team_scoped
  name        = "${var.project_name}-ci"
  description = "CI/CD credential for ${var.project_name} workspace"

  # Nova: インスタンス・サーバーグループ・ボリュームアタッチメント
  access_rules {
    service = "compute"
    method  = "POST"
    path    = "/v2.1/servers"
  }
  access_rules {
    service = "compute"
    method  = "GET"
    path    = "/v2.1/servers"
  }
  access_rules {
    service = "compute"
    method  = "GET"
    path    = "/v2.1/servers/**"
  }
  access_rules {
    service = "compute"
    method  = "PUT"
    path    = "/v2.1/servers/**"
  }
  access_rules {
    service = "compute"
    method  = "DELETE"
    path    = "/v2.1/servers/**"
  }
  access_rules {
    service = "compute"
    method  = "POST"
    path    = "/v2.1/os-server-groups"
  }
  access_rules {
    service = "compute"
    method  = "GET"
    path    = "/v2.1/os-server-groups/**"
  }
  access_rules {
    service = "compute"
    method  = "DELETE"
    path    = "/v2.1/os-server-groups/**"
  }
  access_rules {
    service = "compute"
    method  = "POST"
    path    = "/v2.1/servers/*/os-volume_attachments"
  }
  access_rules {
    service = "compute"
    method  = "GET"
    path    = "/v2.1/servers/*/os-volume_attachments/**"
  }
  access_rules {
    service = "compute"
    method  = "DELETE"
    path    = "/v2.1/servers/*/os-volume_attachments/**"
  }

  # Cinder: ボリューム・スナップショット（CRUD）
  access_rules {
    service = "block-storage"
    method  = "POST"
    path    = "/v3/*/volumes"
  }
  access_rules {
    service = "block-storage"
    method  = "GET"
    path    = "/v3/*/volumes/**"
  }
  access_rules {
    service = "block-storage"
    method  = "PUT"
    path    = "/v3/*/volumes/**"
  }
  access_rules {
    service = "block-storage"
    method  = "DELETE"
    path    = "/v3/*/volumes/**"
  }
  access_rules {
    service = "block-storage"
    method  = "POST"
    path    = "/v3/*/snapshots"
  }
  access_rules {
    service = "block-storage"
    method  = "GET"
    path    = "/v3/*/snapshots/**"
  }
  access_rules {
    service = "block-storage"
    method  = "DELETE"
    path    = "/v3/*/snapshots/**"
  }

  # Neutron: SG のみ（network/subnet/router は catalog が作成済みのため禁止）
  access_rules {
    service = "network"
    method  = "POST"
    path    = "/v2.0/security-groups"
  }
  access_rules {
    service = "network"
    method  = "GET"
    path    = "/v2.0/security-groups/**"
  }
  access_rules {
    service = "network"
    method  = "DELETE"
    path    = "/v2.0/security-groups/**"
  }
  access_rules {
    service = "network"
    method  = "POST"
    path    = "/v2.0/security-group-rules"
  }
  access_rules {
    service = "network"
    method  = "DELETE"
    path    = "/v2.0/security-group-rules/**"
  }
  # Floating IP（デフォルトクォータ 0。申請後に利用可能。07-quota.md 参照）
  access_rules {
    service = "network"
    method  = "POST"
    path    = "/v2.0/floatingips"
  }
  access_rules {
    service = "network"
    method  = "GET"
    path    = "/v2.0/floatingips/**"
  }
  access_rules {
    service = "network"
    method  = "PUT"
    path    = "/v2.0/floatingips/**"
  }
  access_rules {
    service = "network"
    method  = "DELETE"
    path    = "/v2.0/floatingips/**"
  }

  # Swift: コンテナ・オブジェクト（実機未導入。上のコメント参照）
  access_rules {
    service = "object-store"
    method  = "PUT"
    path    = "/v1/**"
  }
  access_rules {
    service = "object-store"
    method  = "GET"
    path    = "/v1/**"
  }
  access_rules {
    service = "object-store"
    method  = "DELETE"
    path    = "/v1/**"
  }

  # Glance: イメージ参照・カスタムアップロード
  access_rules {
    service = "image"
    method  = "GET"
    path    = "/v2/images/**"
  }
  access_rules {
    service = "image"
    method  = "POST"
    path    = "/v2/images"
  }
  access_rules {
    service = "image"
    method  = "DELETE"
    path    = "/v2/images/**"
  }
}
