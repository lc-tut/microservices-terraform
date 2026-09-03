# terraform/platform/openstack/quotas/

グローバルデフォルトクォータ（`catalog/projects/` 等が明示的にティアを
指定しなかった場合に全プロジェクトへ適用される値）を管理する。

## 実装方式

`openstack_compute_quotaset_v2` / `openstack_blockstorage_quotaset_v3` 等
（terraform-provider-openstack が提供）はプロジェクト単位の上書き専用で、
「デフォルト値そのもの」を設定する Terraform リソースは存在しない。
実体は Nova/Cinder の「quota class」API（`PUT .../os-quota-class-sets/default`）
で、これは generic な `restapi` プロバイダー（`Mastercard/terraform-provider-restapi`、
CloudKitty 連携と同じ方針）経由で叩く。

Neutron には同等の API が無い（`neutron.conf` の static 設定のみ）ため、
Neutron のクォータはここでは扱わない（OpenStack インフラ自体の管理範囲。
`documents/terraform/01-overview.md`「管理対象外」参照）。

## 実機で判明した罠

実機検証済み（ローカル DevStack・Polaris 実機の両方。Nova・Cinder とも
Polaris で apply・plan clean・API GET での確認まで完了済み）:

- **`object_id` 指定時の `create_path` 罠**: restapi プロバイダーは `object_id` を
  指定していても `create_path` のデフォルトは `path`（`path/{id}` ではない）。
  指定しないと CREATE(=PUT) が `/os-quota-class-sets` に飛んで 404 になる。
  `create_path` で明示的に `/os-quota-class-sets/default` を指定する。
- **Cinder の URL に project_id を含めない**: Cinder API v3.71（Polaris 実機）は
  project-id-less な URL（token のスコープでプロジェクトを判定する方式）で、
  `"${cinder_url}/${project_id}/..."` のように project_id を付けると
  quota-class-sets に限らず types 等の基本エンドポイントも含め全て
  400 "Malformed request url" になる。古い Cinder（project_id 必須）との
  互換性のため `var.openstack_admin_project_id` は変数として残しているが
  既定は未使用。
- **`ignore_server_additions` は必須**: レスポンスに `fixed_ips`/`floating_ips`/`id`/
  `injected_file_*`/`security_group_rules`/`security_groups` 等、送信していない
  フィールドが `data.quota_class_set` の中（ネストした1階層下）に付加されて
  返る。ローカル DevStack での検証中に一時的に `terraform plan` が
  「1 to change」を示し続ける事象を観測したが、Polaris 実機での apply
  直後の plan では再現せず、複数回確認しても clean（No changes）だった。
  DevStack 側の事象は `ignore_server_additions` 追加前の state が残っていた
  ことによる一時的なものだった可能性が高い。いずれにせよ apply 自体は
  毎回同じ値を PUT するだけなので、仮に drift 表示が出ても実害はない
  （冪等）。
- **`server_groups`/`server_group_members` は quota-class-set API のレスポンスに
  一切現れない**（Nova 側がこのクラスの quota 種別として認識していない模様）。
  実際に効いているかは未確認。

## 本番 Ceph RGW backend への適用時の注意

この root の実機検証（Polaris 実機への apply）は `backend_override.tf` に
よるローカル state で実施した（本番 backend の認証情報がこの検証環境に
無いため）。本番 backend 側の state はまだ空のまま。ただし quota-class-set
は「default」という固定 ID への PUT（シングルトン）なので、空の state から
CI が apply しても同じ値を PUT し直すだけで実害は無い（重複作成の懸念は無い）。
