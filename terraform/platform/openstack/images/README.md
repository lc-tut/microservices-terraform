# terraform/platform/openstack/images/

Ubuntu 24.04 ベースイメージを Glance に登録し、SSH CA 鍵ペアを生成する。
詳細は `ubuntu_image.tf`・`ssh_ca.tf` のコメント参照。

## 「SSH CA 組み込み済み」の実際の意味

この repo にはまだ Packer 等のイメージビルドパイプラインが無いため、
Ubuntu 公式の生の cloud image を加工せずそのまま登録している。CA の
信頼設定（sshd の `TrustedUserCAKeys`）はイメージファイル自体には
焼き込まれておらず、VM 起動時に `modules/lc-vm`（Phase 5・未実装）の
cloud-init が `ssh_ca_public_key_openssh` 出力を使って設定する想定。

## 本番 Ceph RGW backend への適用時の注意

この root の実機適用（Ubuntu image の Glance 登録・SSH CA 鍵生成）は
`backend_override.tf` によるローカル state で実施した（本番 backend の
認証情報がこの検証環境に無いため）。本番 backend 側の state はまだ空のまま。
空の状態で CI が apply すると、既に登録済みの image・CA 鍵とは別に
**新規に重複して作ってしまう**（image は Glance が同名重複を許可する。
CA 鍵は新しい鍵ペアが生成され、既存の鍵で署名した証明書は検証できなくなる）。
本番運用に載せる前に、ローカルで作った state を本番 backend へ移す
（`terraform state push` 等）こと。
