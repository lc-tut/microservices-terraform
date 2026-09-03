# terraform/platform/

管理者のみが apply できる Tier 1 リソース（`documents/terraform/02-repository-structure.md`
「3層アクセスモデル」参照）。性質の異なるものが混在しやすいため、3種類に分けています。

| カテゴリ | ディレクトリ | 何をするところか |
|---|---|---|
| OpenStack リソース | `openstack/<name>/` | OpenStack（や CloudKitty 等その上のサービス）の API を直接操作し、platform 全体の土台（ネットワーク・クォータ・課金ルール）を宣言する。各 `<name>/` が独立した Terraform root |
| インフラ（VM ホスティング） | `infra/<name>/` | platform ソフトウェア（Authentik・CloudKitty 本体等）を動かす VM 自体をプロビジョニングする。各 `<name>/` が独立した Terraform root |
| 概念・IDP/API の登録 | `idp/`・`github/`・`members/` | OpenStack を直接は操作せず、Authentik・GitHub・メンバー台帳といった「組織としての概念」を宣言する |

実機構成の詳細（認証情報の出所・デプロイ手順・実際に採用した構成等）は各ディレクトリの
`README.md` を参照してください。設計そのもの（なぜこの形にしたか）は
`documents/terraform/` を参照してください。
