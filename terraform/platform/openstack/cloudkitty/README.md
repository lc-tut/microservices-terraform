# terraform/platform/openstack/cloudkitty/

CloudKitty の Hashmap 課金ルール（Credit 建ての正式単価）を IaC 管理する。
方針の詳細は `documents/terraform/16-implementation-phases.md`
「[P5] CloudKitty の導入方針」、単価の定義は `documents/terraform/09-costs.md`。

CloudKitty 本体（VM・コンテナ）のプロビジョニングは
`terraform/platform/infra/cloudkitty-infra/`。実機の collector 種別・
ネットワーク構成・認証情報の出所など、環境固有の詳細は同ディレクトリの
`README.md` を参照。

## service 名の対応

CloudKitty 内部の「サービス名」は collector 側のメトリクス設定の `alt_name`
と一致させる必要がある: `vcpu` / `memory` / `volume` / `floating_ip`。
ここで作る hashmap service 名もそれに合わせる（`service_rate` は
service 直付けの flat mapping = そのサービスの qty 全体に単価を掛ける）。

## 認証

ambient な `openstack` provider（`OS_CLOUD` / `clouds.yaml`）を使う。
apply 時に使う cloud 名・スコープは環境ごとに異なる（README や
`terraform/platform/infra/cloudkitty-infra/README.md` の「デプロイ」節を参照）。
トークンは `restapi` 経由で CloudKitty API にそのまま渡り、CloudKitty 側の
`keystone_authtoken` 設定で検証される。

## 未設定のリソース

オブジェクトストレージ（0.0005 Credit/GB-hour, `09-costs.md`）は
Swift/S3(RGW) が無い環境では未設定。RGW 導入時に対応する使用量メトリクスと
`module "object_storage"` を足す。

## 本番 Ceph RGW backend への適用時の注意

この root の実機適用は `backend_override.tf` によるローカル state で実施した
（本番 backend の認証情報がこの検証環境に無いため）。本番 backend 側の
state はまだ空のまま。**CloudKitty の Hashmap サービスは名前の一意性を
サーバー側で強制しない**ため、空の state から CI が apply すると
`vcpu`/`memory`/`volume`/`floating_ip` の重複サービス・重複 mapping が
作られ、同じ使用量が二重に課金される。本番運用に載せる前に、ローカルで
作った state を本番 backend へ移す（`terraform state push` 等）こと。
