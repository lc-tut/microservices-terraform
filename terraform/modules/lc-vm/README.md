# modules/lc-vm

`workspaces/` から呼び出す汎用 VM モジュール。`documents/terraform/16-implementation-phases.md`
Phase 5・`documents/terraform/12-openstack-resources.md`「モジュールライブラリ」を実装したもの。

内包するリソース: `openstack_compute_instance_v2` + `openstack_blockstorage_volume_v3`
（独立リソースとして作成し、instance には既存 volume からの boot として渡す）+
`openstack_networking_secgroup_v2` / `_rule_v2`。

## 前提

- 呼び出し元(`workspaces/<name>/`)が動く project に、`catalog/projects/<name>/` が
  作成した同名の network/subnet が存在すること(`var.project_name` で解決)。
- `openstack_compute_keypair_v2` は使わない方針(SSH は CLI 発行の短命証明書)。
  そのため `var.ssh_ca_public_key` に CA 公開鍵を渡す必要がある
  （`platform/openstack/images` の output `ssh_ca_public_key_openssh`。
  `terraform_remote_state` で読むか、呼び出し元が変数として受け渡す）。
- `var.flavor` は実機に存在する flavor 名を渡すこと。`lc-micro`/`lc-small` 等の
  専用 flavor(`platform/openstack/flavors/`)はまだ実装されていないため、
  現状は `m1.medium` 等の Kolla 既定 flavor を指定する。

## 使用例

```hcl
module "app" {
  source            = "../../modules/lc-vm"
  name              = "my-app"
  project_name      = "my-product"
  flavor            = "m1.medium"
  image             = "ubuntu-24.04"
  volume_size_gb    = 40
  ssh_ca_public_key = data.terraform_remote_state.images.outputs.ssh_ca_public_key_openssh

  user_data = <<-EOT
    #cloud-config
    packages: [nginx]
  EOT

  security_group_rules = [
    {
      direction        = "ingress"
      protocol         = "tcp"
      port_range_min   = 443
      port_range_max   = 443
      remote_ip_prefix = "0.0.0.0/0"
    }
  ]
}
```

## 設計メモ

- **boot-from-volume を独立リソース化**: `platform/infra/*-infra/` 系の root は
  `openstack_compute_instance_v2.block_device` に `source_type = "image"` を
  inline で書いて Cinder に暗黙生成させているが、本モジュールは
  `openstack_blockstorage_volume_v3.root` を先に作り、instance 側は
  `source_type = "volume"` でそれを参照する。volume が state 上で独立した
  リソースになるため、呼び出し元は resize・snapshot・instance の
  `-replace` 後の付け替えなどを volume 側だけで扱える。
  `delete_on_termination = false` にしているのもそのため
  （instance 削除時に volume を巻き込まない。volume 自体の削除は
  `openstack_blockstorage_volume_v3.root` を module ごと destroy すれば行われる）。
- **SSH CA trust の注入**: `hashicorp/cloudinit` provider の
  `cloudinit_config` data source で multipart 合成している。1パート目
  （`templates/ca-trust.yaml.tftpl`）が常に `TrustedUserCAKeys` を設定し、
  `var.user_data` があれば2パート目として追加される。
  `platform/openstack/images/ssh_ca.tf` のコメントにあった
  「Phase 5 modules/lc-vm 側の cloud-init の責務（未実装）」を解消するもの。
- **明示的な `openstack_networking_port_v2` は作らない**
  （VPC Gateway 強制方針のため禁止。`12-openstack-resources.md` 参照）。
  instance の `network{}` ブロックが暗黙ポートを作る。
- **`allow_ssh_from_project_subnet`**（既定 true）は同一プロジェクト subnet
  からの SSH/ICMP のみを許可する最小限のデフォルト。フロート IP 経由で
  外部公開する場合や追加ポートは `var.security_group_rules` で明示する。
