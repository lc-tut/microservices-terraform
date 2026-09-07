# network/subnet はこの root では作らない。所属チームの
# catalog/teams/<team-name>/ が /26 を払い出したチーム専用ネットワークを使う。
# 受け取った名前を output で workspaces/ に渡すだけ。
data "openstack_networking_network_v2" "team" {
  name = var.team_network_name
}

# 同じチームのプロジェクト同士は Keystone project もネットワークも共有するため、
# ネットワーク上の境界が無い。境界は「同一 SG のメンバーからの ingress だけ許可」
# するこの SG で作る。remote_group_id は SG 単位なので、別プロジェクトの VM は
# この SG を付けた VM に到達できない。VM は必ずこの SG を付けて起動する。
resource "openstack_networking_secgroup_v2" "baseline" {
  provider             = openstack.team_scoped
  name                 = "${var.project_name}-baseline"
  description          = "${var.project_name}: 同一プロジェクト内のみ疎通を許可するベースライン SG"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "baseline_intra_project" {
  provider          = openstack.team_scoped
  security_group_id = openstack_networking_secgroup_v2.baseline.id
  description       = "同一プロジェクトの VM 間のみ許可"

  direction       = "ingress"
  ethertype       = "IPv4"
  remote_group_id = openstack_networking_secgroup_v2.baseline.id
}

resource "openstack_networking_secgroup_rule_v2" "baseline_egress" {
  provider          = openstack.team_scoped
  security_group_id = openstack_networking_secgroup_v2.baseline.id
  description       = "外向き通信（int-router 経由）"

  direction        = "egress"
  ethertype        = "IPv4"
  remote_ip_prefix = "0.0.0.0/0"
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

  # Neutron: SG のみ（network/subnet/router interface は catalog が作成済み）
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
