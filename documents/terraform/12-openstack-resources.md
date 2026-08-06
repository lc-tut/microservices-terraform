# OpenStack リソース管理方針

LC-Cloud (OpenStack) が提供するすべての Terraform リソースを、
3 層アクセスモデルに基づいて分類・管理方針を定義します。

---

## 設計原則

- **VPC Gateway 強制**: 外向き通信はすべてプラットフォーム管理の VPC Gateway を経由させる。
  独自 NAT・独自 LB は禁止。Floating IP はデフォルトクォータ 0 のため禁止と同等だが、
  billing-accounts で申請・承認後にオプトインで利用可能（課金あり）。
- **IP 払い出し管理**: Platform が `openstack_networking_subnetpool_v2` で IP 帯域を管理し、
  `catalog/projects/` がプロジェクトごとに /24 を割り当てる。ユーザーは `data` 参照のみ。
- **SSH 鍵の非 Terraform 管理**: `openstack_compute_keypair_v2` は
  CLI ツール（Authentik SSO + 証明書発行）で代替する。Terraform には記述しない。
- **Application Credential + Access Rules**: `catalog/projects/` が
  Workspace の CI/CD 用に Access Rules 付きの制限済み認証情報を発行する。
  Access Rules は OpenStack API レベルで強制されるため、
  Terraform コードに書いても拒否される。
- **Octavia (LB) 制限**: LB 本体・Listener・Pool は `catalog/projects/` が作成・管理。
  Workspace は `openstack_lb_member_v2` で catalog 管理の pool に VM を追加するのみ。
  独自 LB の作成は禁止。K8s アプリは Kubernetes Ingress Controller 経由。

---

## 凡例

| 記号 | 説明 |
| --- | --- |
| 🔴 Tier 1 | `platform/` 管理者のみ |
| 🟡 Tier 2 | `catalog/projects/` 権限者が apply |
| 🟢 Tier 3 | `workspaces/` ユーザーが自由に記述 |
| ⛔ BLOCKED | Access Rules で API レベルブロック |
| 📖 data のみ | `resource` 作成不可・`data` 参照のみ |
| 🛠 CLI | Terraform 外（CLI ツール）で管理 |

---

## Nova（Compute）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_compute_instance_v2` | 🟢 Tier 3 | `workspaces/` | 推奨: `modules/lc-vm` 経由 |
| `openstack_compute_keypair_v2` | 🛠 CLI | — | CLI が SSH 証明書で代替。Terraform 記述不可 |
| `openstack_compute_servergroup_v2` | 🟢 Tier 3 | `workspaces/` | anti-affinity / affinity |
| `openstack_compute_volume_attach_v2` | 🟢 Tier 3 | `workspaces/` | instance + volume を同一スタック推奨 |
| `openstack_compute_interface_attach_v2` | ⛔ BLOCKED | — | VPC Gateway 強制のため禁止 |
| `openstack_compute_flavor_v2` | 🔴 Tier 1 | `platform/` | lc-micro / lc-small 等を platform が定義 |
| `openstack_compute_aggregate_v2` | 🔴 Tier 1 | `platform/` | ホストアグリゲート |
| `openstack_compute_quotaset_v2` | 🔴 Tier 1 | `platform/quotas/` | プロジェクトごとのクォータ |

---

## Cinder（Block Storage）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_blockstorage_volume_v3` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_blockstorage_snapshot_v3` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_blockstorage_volume_attach_v3` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_blockstorage_volume_type_v3` | 🔴 Tier 1 | `platform/` | SSD / HDD 等の volume type 定義 |
| `openstack_blockstorage_quotaset_v3` | 🔴 Tier 1 | `platform/quotas/` | |

---

## Neutron（Networking）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_networking_network_v2` (共有・外部) | 🔴 Tier 1 | `platform/network/` | platform backbone |
| `openstack_networking_network_v2` (プロジェクト専用) | 🟡 Tier 2 | `catalog/projects/` | private network |
| `openstack_networking_subnet_v2` | 🟡 Tier 2 | `catalog/projects/` | subnetpool から /24 を払い出し |
| `openstack_networking_subnetpool_v2` | 🔴 Tier 1 | `platform/network/` | IP 帯域のマスタープール |
| `openstack_networking_router_v2` | 🔴 Tier 1 | `platform/network/` | VPC Gateway ルーター |
| `openstack_networking_router_interface_v2` | 🟡 Tier 2 | `catalog/projects/` | VPC Gateway へ project subnet を接続 |
| `openstack_networking_router_route_v2` | 🔴 Tier 1 | `platform/network/` | 静的ルート管理 |
| `openstack_networking_floatingip_v2` | 🟢 Tier 3 | `workspaces/` | デフォルトクォータ 0。billing-accounts 申請後に利用可能。課金あり |
| `openstack_networking_floatingip_associate_v2` | 🟢 Tier 3 | `workspaces/` | 同上 |
| `openstack_networking_port_v2` | ⛔ BLOCKED | — | 明示的なポート作成禁止。インスタンス生成時の暗黙ポートは Nova API 経由のため影響なし |
| `openstack_networking_secgroup_v2` | 🟢 Tier 3 | `workspaces/` | プロジェクトスコープ内 |
| `openstack_networking_secgroup_rule_v2` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_networking_rbac_policy_v2` | 🔴 Tier 1 | `platform/network/` | ネットワーク共有ポリシー |
| `openstack_networking_trunk_v2` | ⛔ BLOCKED | — | platform が管理 |
| `openstack_networking_qos_policy_v2` | 🔴 Tier 1 | `platform/` | QoS ポリシー定義 |
| `openstack_networking_qos_bandwidth_limit_rule_v2` | 🔴 Tier 1 | `platform/` | |
| `openstack_networking_quota_v2` | 🔴 Tier 1 | `platform/quotas/` | |

---

## Glance（Image）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_images_image_v2` (ベースイメージ) | 🔴 Tier 1 | `platform/images/` | SSH CA 組み込み済み |
| `openstack_images_image_v2` (カスタムイメージ) | 🟢 Tier 3 | `workspaces/` | Harbor / Packer 推奨 |
| `openstack_images_image_access_v2` | 🔴 Tier 1 | `platform/images/` | プロジェクト間でのイメージ共有 |
| `openstack_images_image_access_accept_v2` | 🟢 Tier 3 | `workspaces/` | 共有イメージの受け取り |

---

## Keystone（Identity）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_identity_project_v3` | 🔴 Tier 1 | `platform/idp/` | プロジェクト作成は admin のみ |
| `openstack_identity_user_v3` | 🔴 Tier 1 | `platform/idp/` | SCIM 経由で Authentik が provisioning |
| `openstack_identity_group_v3` | 🔴 Tier 1 | `platform/idp/` | SCIM 経由で Authentik が provisioning |
| `openstack_identity_role_v3` | 🔴 Tier 1 | `platform/idp/` | |
| `openstack_identity_role_assignment_v3` | 🔴 Tier 1 | `platform/idp/` | |
| `openstack_identity_application_credential_v3` | 🟡 Tier 2 | `catalog/projects/` | Access Rules 付き。Workspace CI/CD 用 |
| `openstack_identity_endpoint_v3` | 🔴 Tier 1 | `platform/` | admin のみ |
| `openstack_identity_service_v3` | 🔴 Tier 1 | `platform/` | admin のみ |

---

## Octavia（Load Balancer）

LB 本体・Listener・Pool の新規作成は禁止。
`catalog/projects/` が作成した LB pool への member 追加のみ Tier 3 で許可。

| リソース | 分類 | 備考 |
| --- | --- | --- |
| `openstack_lb_loadbalancer_v2` | ⛔ BLOCKED | catalog が管理。Workspace 作成不可 |
| `openstack_lb_listener_v2` | ⛔ BLOCKED | 同上 |
| `openstack_lb_pool_v2` | ⛔ BLOCKED | 同上 |
| `openstack_lb_member_v2` | 🟢 Tier 3 | `workspaces/` | catalog 管理の pool に VM を追加する用途のみ |
| `openstack_lb_monitor_v2` | ⛔ BLOCKED | |
| `openstack_lb_l7policy_v2` | ⛔ BLOCKED | |
| `openstack_lb_l7rule_v2` | ⛔ BLOCKED | |
| `openstack_lb_quota_v2` | 🔴 Tier 1 | `platform/quotas/` |

---

## Designate（DNS）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_dns_zone_v2` | 🟡 Tier 2 | `catalog/projects/` | プロジェクトへの DNS ゾーン割り当て |
| `openstack_dns_recordset_v2` | 🟢 Tier 3 | `workspaces/` | ゾーン内の A/CNAME 等を自由に追加 |

---

## Barbican（Key Management）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_keymanager_secret_v1` | 🟢 Tier 3 | `workspaces/` | TLS 証明書・API キー等 |
| `openstack_keymanager_container_v1` | 🟢 Tier 3 | `workspaces/` | 証明書チェーンのコンテナ |
| `openstack_keymanager_order_v1` | 🟢 Tier 3 | `workspaces/` | 鍵生成オーダー |

---

## Manila（Shared File System）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_sharedfilesystem_share_v2` | 🟢 Tier 3 | `workspaces/` | NFS / CIFS 共有 |
| `openstack_sharedfilesystem_sharenetwork_v2` | 🟡 Tier 2 | `catalog/projects/` | プロジェクトネットワークへのバインド |
| `openstack_sharedfilesystem_snapshot_v2` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_sharedfilesystem_share_access_v2` | 🟢 Tier 3 | `workspaces/` | アクセス制御リスト |

---

## Swift（Object Storage）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_objectstorage_container_v1` | 🟢 Tier 3 | `workspaces/` | S3 互換バケット相当 |
| `openstack_objectstorage_object_v1` | 🟢 Tier 3 | `workspaces/` | 設定ファイル等の小さなオブジェクト向け |
| `openstack_objectstorage_tempurl_v1` | 🟢 Tier 3 | `workspaces/` | 署名付き一時 URL |

---

## Trove（Database）

| リソース | 分類 | 管理フォルダ | 備考 |
| --- | --- | --- | --- |
| `openstack_db_instance_v1` | 🟢 Tier 3 | `workspaces/` | Managed MySQL / PostgreSQL 等 |
| `openstack_db_database_v1` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_db_user_v1` | 🟢 Tier 3 | `workspaces/` | |
| `openstack_db_configuration_v1` | 🟢 Tier 3 | `workspaces/` | |

---

## Kubernetes リソース（Tier 3）

Deployment / Service / Ingress は ArgoCD / FluxCD で管理。
Terraform は下表のリソースのみ担当する。

| リソース | 備考 |
| --- | --- |
| `kubernetes_persistent_volume_claim_v1` | ストレージ要求（StorageClass は platform 管理） |
| `kubernetes_secret_v1` | Barbican や SOPS と連携推奨 |
| `kubernetes_config_map_v1` | アプリ設定 |
| `kubernetes_service_account_v1` | IRSA 相当の権限分離 |
| `kubernetes_namespace_v1` | 📖 data のみ（`catalog/projects/` が作成） |

---

## data source 一覧（resource 作成不可）

Workspace では以下を `data` ブロックで参照する。

```hcl
# 払い出されたネットワーク・サブネット
data "openstack_networking_network_v2" "project" {
  name = var.network_name
}

data "openstack_networking_subnet_v2" "project" {
  name = var.subnet_name
}

# 利用可能なフレーバー・イメージ
data "openstack_compute_flavor_v2" "small" {
  name = "lc-small"
}

data "openstack_images_image_v2" "ubuntu" {
  name        = "ubuntu-24.04-lts"
  most_recent = true
}

# DNS ゾーン（catalog/projects/ が作成済み）
data "openstack_dns_zone_v2" "project" {
  name = "${var.project_name}.lc-cloud.example."
}

# Kubernetes Namespace（catalog/projects/ が作成済み）
data "kubernetes_namespace_v1" "project" {
  metadata {
    name = var.project_name
  }
}
```

---

## Access Rules 仕様

`catalog/projects/<name>/lc_cloud.tf` で Workspace 用の
Application Credential を発行する際に指定する Access Rules。

```hcl
resource "openstack_identity_application_credential_v3" "workspace_ci" {
  name        = "${var.project_name}-ci"
  description = "CI/CD credential for ${var.project_name} workspace"

  access_rules = [
    # Nova: インスタンス・サーバーグループ（CRUD）
    { method = "POST",   path = "/v2.1/servers" },
    { method = "GET",    path = "/v2.1/servers" },
    { method = "GET",    path = "/v2.1/servers/**" },
    { method = "PUT",    path = "/v2.1/servers/**" },
    { method = "DELETE", path = "/v2.1/servers/**" },
    { method = "POST",   path = "/v2.1/os-server-groups" },
    { method = "GET",    path = "/v2.1/os-server-groups/**" },
    { method = "DELETE", path = "/v2.1/os-server-groups/**" },
    # Nova: ボリュームアタッチメント
    { method = "POST",   path = "/v2.1/servers/*/os-volume_attachments" },
    { method = "GET",    path = "/v2.1/servers/*/os-volume_attachments/**" },
    { method = "DELETE", path = "/v2.1/servers/*/os-volume_attachments/**" },
    # Cinder: ボリューム・スナップショット（CRUD）
    { method = "POST",   path = "/v3/*/volumes" },
    { method = "GET",    path = "/v3/*/volumes/**" },
    { method = "PUT",    path = "/v3/*/volumes/**" },
    { method = "DELETE", path = "/v3/*/volumes/**" },
    { method = "POST",   path = "/v3/*/snapshots" },
    { method = "GET",    path = "/v3/*/snapshots/**" },
    { method = "DELETE", path = "/v3/*/snapshots/**" },
    # Neutron: SG（network / subnet / router は禁止）
    { method = "POST",   path = "/v2.0/security-groups" },
    { method = "GET",    path = "/v2.0/security-groups/**" },
    { method = "DELETE", path = "/v2.0/security-groups/**" },
    { method = "POST",   path = "/v2.0/security-group-rules" },
    { method = "DELETE", path = "/v2.0/security-group-rules/**" },
    # Neutron: Floating IP（デフォルトクォータ 0。申請後に利用可能）
    { method = "POST",   path = "/v2.0/floatingips" },
    { method = "GET",    path = "/v2.0/floatingips/**" },
    { method = "PUT",    path = "/v2.0/floatingips/**" },
    { method = "DELETE", path = "/v2.0/floatingips/**" },
    # Octavia: catalog 管理の LB pool への member 追加のみ
    { method = "POST",   path = "/v2/lbaas/pools/*/members" },
    { method = "GET",    path = "/v2/lbaas/pools/*/members/**" },
    { method = "DELETE", path = "/v2/lbaas/pools/*/members/**" },
    # Swift: コンテナ・オブジェクト
    { method = "PUT",    path = "/v1/**" },
    { method = "GET",    path = "/v1/**" },
    { method = "DELETE", path = "/v1/**" },
    # Glance: イメージ（参照・カスタムアップロード）
    { method = "GET",    path = "/v2/images/**" },
    { method = "POST",   path = "/v2/images" },
    { method = "DELETE", path = "/v2/images/**" },
    # Designate: 割り当て済みゾーン内の recordset のみ
    { method = "GET",    path = "/v2/zones/**" },
    { method = "POST",   path = "/v2/zones/*/recordsets" },
    { method = "PUT",    path = "/v2/zones/*/recordsets/**" },
    { method = "DELETE", path = "/v2/zones/*/recordsets/**" },
    # Barbican: シークレット
    { method = "POST",   path = "/v1/secrets" },
    { method = "GET",    path = "/v1/secrets/**" },
    { method = "DELETE", path = "/v1/secrets/**" },
    { method = "POST",   path = "/v1/containers" },
    { method = "GET",    path = "/v1/containers/**" },
    { method = "DELETE", path = "/v1/containers/**" },
    # Manila: 共有ファイルシステム・アクセスルール
    { method = "POST",   path = "/v2/shares" },
    { method = "GET",    path = "/v2/shares/**" },
    { method = "DELETE", path = "/v2/shares/**" },
    { method = "POST",   path = "/v2/share-access-rules" },
    { method = "GET",    path = "/v2/share-access-rules/**" },
    { method = "DELETE", path = "/v2/share-access-rules/**" },
    { method = "GET",    path = "/v2/share-snapshots/**" },
    { method = "POST",   path = "/v2/share-snapshots" },
    { method = "DELETE", path = "/v2/share-snapshots/**" },
    # Trove: DB インスタンス
    { method = "POST",   path = "/v1.0/*/instances" },
    { method = "GET",    path = "/v1.0/*/instances/**" },
    { method = "DELETE", path = "/v1.0/*/instances/**" },
    # Trove: DB・ユーザー・バックアップ
    { method = "POST",   path = "/v1.0/*/instances/*/databases" },
    { method = "GET",    path = "/v1.0/*/instances/*/databases" },
    { method = "DELETE", path = "/v1.0/*/instances/*/databases/**" },
    { method = "POST",   path = "/v1.0/*/instances/*/users" },
    { method = "GET",    path = "/v1.0/*/instances/*/users" },
    { method = "DELETE", path = "/v1.0/*/instances/*/users/**" },
    { method = "POST",   path = "/v1.0/*/backups" },
    { method = "GET",    path = "/v1.0/*/backups/**" },
    { method = "DELETE", path = "/v1.0/*/backups/**" },
  ]
}
```

---

## モジュールライブラリ（`terraform/modules/`）

Workspace 向けに提供する便利モジュール一覧。
使用は任意。生の OpenStack / Kubernetes リソースを直接書いても良い。

| モジュール | 内包するリソース | 主な省略設定 |
| --- | --- | --- |
| `modules/lc-vm` | `openstack_compute_instance_v2` + `openstack_blockstorage_volume_v3` + `openstack_networking_secgroup_v2` | フレーバー名・イメージ・ネットワーク参照を自動解決 |
| `modules/lc-k8s-app` | `kubernetes_persistent_volume_claim_v1` + `kubernetes_secret_v1` + `kubernetes_config_map_v1` | Namespace は `data` で自動参照 |
| `modules/lc-object-bucket` | `openstack_objectstorage_container_v1` + CORS / lifecycle 設定 | S3 互換 URL を output |
| `modules/lc-db` | `openstack_db_instance_v1` + `openstack_db_database_v1` + `openstack_db_user_v1` | flavor / type を自動選択 |
| `modules/lc-dns-record` | `openstack_dns_recordset_v2` | ゾーン名を `data` で自動参照 |

---

## フォルダ別まとめ

| フォルダ | 管理リソース |
| --- | --- |
| `platform/network/` | subnetpool・外部 network・VPC Gateway router・RBAC policy |
| `platform/images/` | base image・image access |
| `platform/quotas/` | compute / storage / network / LB quota |
| `platform/idp/` | project・user・group・role・role assignment（SCIM 経由も含む） |
| `catalog/projects/<name>/` | project network・subnet（/24）・router interface・application credential（Access Rules 付き）・dns zone |
| `workspaces/<name>/` | インスタンス・ボリューム・SG・オブジェクトストレージ・DNS recordset・シークレット・DB・Kubernetes リソース |
