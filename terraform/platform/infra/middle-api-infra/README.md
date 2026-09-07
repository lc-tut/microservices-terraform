# infra-api / billing-api 用 VM

OpenStack 上に `lcn-infra-api` と `lcn-billing-api` を1台ずつ作る、サービス別の Terraform root。
認証情報受領前に VM 定義とモック検証を準備したもの。実環境への plan / apply は未実施。

## ディレクトリ構成

| ディレクトリ | 管理する VM | CI 入力 |
| --- | --- | --- |
| [openstack/](openstack/README.md) | lcn-infra-api 1台 | `MIDDLE_OPENSTACK_VM_CONFIG` |
| [billing/](billing/README.md) | lcn-billing-api 1台 | `MIDDLE_BILLING_VM_CONFIG` |

それぞれが backend・設定例・provider lock・テストを持つ独立した root。
この親ディレクトリでは Terraform を実行しない。VM 名は変更しない。

## 作成するもの

- VM 2台。それぞれイメージから Cinder ルートボリュームで起動する。
- VM ごとの Neutron ポート・専用 Security Group・指定送信元からの SSH 許可。
- 指定した場合だけ Floating IP とその関連付け。
- cloud-init で SSH パスワード認証を無効化し、`/opt/lcn-<infra|billing>-api/PROVISIONING.txt` を作成。

ネットワーク・サブネット・イメージ・flavor・SSH keypair は既存のものを使用する。
サブネット ID から所属ネットワークを解決する。イメージは ID を固定する。
鍵の生成・秘密鍵の保存は Terraform では行わない。

VM の作成までを各 root の完了範囲とする。
Docker / アプリ / PostgreSQL / Vault Agent / reverse proxy / DNS / TLS はまだ配備しない。
OS や運用方式が確定した後に、下記のアプリ配備条件を埋める。

## 認証情報なしで検証する

Terraform `~> 1.10` とインターネット接続（provider 取得用）が必要。
`openstack/` と `billing/` のそれぞれで実行する。tfvars の作成やクラウドへのログインは不要。

```sh
terraform init -backend=false -input=false
terraform fmt -check -recursive
terraform validate
terraform test
```

テストは全 run に mock provider を使い、OpenStack の実 API や GCS state を操作しない。
通常の `terraform plan` は認証情報と実環境の入力を受け取った後に行う。
2026-09-07 に Terraform 1.13.5 / OpenStack provider 3.4.0 で 両 root の validate とモックテスト各4件（計8件）が成功。
確認対象は各 root が対象 VM 1台だけを管理すること、SSH 限定の既定値、任意の Floating IP / API 許可、全世界向け SSH と infra の管理ポートの拒否。
VM 起動・実ネットワーク到達性・cloud-init 実行は未検証。

## PL から受け取るもの・確認すること

| 項目 | 必要な内容 |
| --- | --- |
| VM 作成先 | OpenStack endpoint、region、対象 project の ID / 名前 |
| OpenStack 認証 | 対象 project の資格情報。VM / volume / port / SG と、必要なら Floating IP の作成権限 |
| state 認証 | GCS bucket `linuxclub-network-cloud-terraform-state` への読み書き・ロック用 Google 認証。OpenStack とは別 |
| OS | cloud-init 対応イメージ ID、標準 SSH ユーザー名、CPU architecture |
| スペック | 各 VM の flavor ID と root volume GB。例の40 GBは確定値ではない |
| ネットワーク | 各 VM の IPv4 subnet ID、空き IP、ルーティング / DNS / 外向き通信 |
| SSH | 既存 keypair 名、対応する秘密鍵の受け渡し方法、管理端末 / VPN / 踏み台の実送信元 CIDR |
| 外部 IP | Floating IP の要否。必要なら外部 network 名と router 経路 |
| 配備範囲 | VM 作成までか、API 起動・疎通確認まで含むか |

同名 VM が既に存在する場合は、既存 state / import 対象を確認してから進める。

## 認証情報受領後の手順

### 1. 入力と認証

対象 root の `terraform.tfvars.example` を `terraform.tfvars` にコピーし、すべての `REPLACE_*` と例示 CIDR を実値へ差し替える。
コピー先は既存 `.gitignore` の対象。認証情報は記入しない。
不要なら `floating_ip_pool`、`api_allowed_cidrs`、`admin_allowed_cidrs` を省略する。

Application Credential なら `OS_AUTH_TYPE=v3applicationcredential` と
`OS_AUTH_URL`、`OS_APPLICATION_CREDENTIAL_ID`、`OS_APPLICATION_CREDENTIAL_SECRET`、`OS_REGION_NAME` を環境変数に設定する。
または既存の `local/clouds.yaml` と `OS_CLIENT_CONFIG_FILE` / `OS_CLOUD` を使用する。
受け取った方式のどちらか一方に揃え、別環境の認証設定が残っていないことを確認する。
認証情報の値はリポジトリ・cloud-init・コマンド例へ貼り付けない。

GCS backend は指定された ADC / Workload Identity 等で認証する。
既存 bucket 内で以下の prefix に分ける。

- `tfstate/terraform/platform/infra/middle-api-infra/openstack`
- `tfstate/terraform/platform/infra/middle-api-infra/billing`

旧構成は実 apply 前のため、この作業では state 移行を行っていない。
別途旧構成を適用済みの場合は、新規 apply 前に既存 state からの移行を確認する。
state 認証が未着なら、ローカル state に切り替えて実 apply せず受領を待つ。

実環境に接続できる端末で、OpenStack CLI があれば読み取り確認する。

```sh
openstack project show <PROJECT_ID>
openstack image show <IMAGE_ID>
openstack flavor show <FLAVOR_ID>
openstack subnet show <SUBNET_ID>
openstack keypair show <KEYPAIR_NAME>
openstack quota show <PROJECT_ID>
openstack server list
```

イメージの最小ディスク・flavor の要件と、2台分の vCPU / RAM / volume / SG / port の quota を確認する。
SSH 許可元は VM から見える送信元 CIDR を指定する。
Floating IP なしの場合は private IP への VPN / 踏み台等の経路が必要。

### 2. 実 plan と適用

既存運用どおり PR レビューを通して適用する。手動適用を担当する場合は、対象 root（`openstack/` または `billing/`）で以下を実行する。

```sh
terraform init -reconfigure -input=false
terraform plan -input=false -out=tfplan
terraform show -no-color tfplan
# project / region / 対象 VM の構成 / 許可元 / 差分をレビューした後
terraform apply tfplan
terraform output vm
```

新規 state かつ例の既定構成なら各 root で4リソース追加（VM 1、port 1、SG 1、SSH rule 1）が目安。
Nova が作るルートボリュームはこの数とは別に OpenStack 上に作成される。
API 許可は CIDR ごとに rule、Floating IP は各 VM につき2リソース増える。
既存リソースの削除・置換が現れたら理由を確認する。

### 3. VM の受け入れ確認

- `openstack server show <VM_ID>` で2台とも `ACTIVE`、想定する image / flavor / IP であること。
- 許可した管理元から `ssh -i <PRIVATE_KEY_PATH> <IMAGE_USER>@<IP>` で接続できること。
- VM 内で `sudo cloud-init status --wait --long` が正常終了し、`PROVISIONING.txt` が存在すること。
- SG に余分な受信許可がなく、許可外の送信元から SSH / API / DB へ到達できないこと。
- 初回適用後の `terraform plan -input=false` が変更なしになること。

この段階で API は稼働していない。`ACTIVE` やマーカーだけで API 利用開始を報告しない。

## API 配備へ進む場合

隣接する `lcn-infra-api/deploy/` と `lcn-billing-api/deploy/k8s/` は Kubernetes 向け。
VM 上でコンテナ / systemd 等のどれを使うかを決めてから移す。

| サービス | 現在の実装・配備定義から必要になるもの |
| --- | --- |
| infra-api | api / worker / reconciler、事前 migrate、PostgreSQL、OpenStack サービス資格情報、認証連携 |
| billing-api | API (8080) / 管理 API (8081)、事前 migrate、PostgreSQL、aggregator 定期実行、CloudKitty / OpenStack 接続、管理 Bearer token |
| 共通 | 固定イメージタグ / digest、永続データ・バックアップ、再起動、ログ、TLS / reverse proxy、秘密情報の供給方式 |

8080は forward-auth 済み reverse proxy の実送信元だけに許可する。
proxy で外部由来の認証ヘッダを除去・再設定し、直アクセス拒否を実測する。
共有 subnet 全体の CIDR を許可すると別 VM が認証を迂回できる場合があるため、proxy の実送信元まで絞る。
billing の8081は管理 Bearer token と Terraform 実行元制限を両方用意してから開ける。
5432、80 / 443の受信許可は各 root では作らない。
Kubernetes 向け Vault 認証をそのまま VM に流用せず、VM の認証方式を確定する。

VM の `prevent_destroy` は設定変更による置換も止める。
image / user_data 等の変更で置換が必要ならデータ保全と更新方法を先に決める。
ルートボリュームは VM 削除時に削除される設定。`prevent_destroy` はバックアップの代わりではない。
resource 設定自体の削除や OpenStack からの直接削除も保護しない。

## GitHub Actions

既存の `scripts/detect-platform-stacks.sh` が `backend.tf` を検出し、Plan / Apply 対象になる。
GitHub Actions variable `MIDDLE_OPENSTACK_VM_CONFIG` / `MIDDLE_BILLING_VM_CONFIG` に、それぞれ1台分の `vm_config` の中身を JSON オブジェクトで登録する。
構造は tfvars 例と同じで、外側に `vm_config` キーを重ねない。workflow が対象 root に対応する変数を選んで `TF_VAR_vm_config` として渡す。
ローカル tfvars は CI に送られないため、merge 前に実値の登録が必要。
認証は既存 workflow の OpenStack secrets / GCS Workload Identity を使用する。
CI 実行元から OpenStack API に到達できることも認証情報受領後に確認する。

GitHub variable / secrets の登録、実環境 plan / apply は行っていない。

参考: [OpenStack VM resource](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2)、
[Terraform mock provider](https://developer.hashicorp.com/terraform/language/tests/mocking)。
