# terraform/platform/openstack/network/

VPC Gateway ルーター・IP 帯域マスタープール（subnetpool）・外部ネットワーク
共有ポリシーを管理する。実機で判明した内容は各 `.tf` のコメント
（`gateway.tf`・`external_network.tf`・`subnetpool.tf`）にまとめてある。

## 本番 Ceph RGW backend への適用時の注意

この root の実機検証（Polaris 実機への apply。既存 router・RBAC ポリシーの
import 含む）は `backend_override.tf` によるローカル state で実施した
（本番 backend の認証情報がこの検証環境に無いため）。本番 backend 側の
state はまだ空のまま。空の状態で CI が apply すると、`gateway.tf` が
import 済みの既存 router（`lc-dev-router`）とは別に**新規ルーターを重複して
作ってしまう**（Neutron はルーター名の一意性を強制しない）。
`external_network.tf` の RBAC ポリシーも同様に重複しうる。本番運用に載せる前に、
ローカルで作った state を本番 backend へ移す（`terraform state push` 等）こと。
