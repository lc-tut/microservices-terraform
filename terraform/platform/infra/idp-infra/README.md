# terraform/platform/infra/idp-infra

`terraform/platform/idp/`（Authentik の flow / stage / brand 等を宣言する root）が
接続する **Authentik インスタンスそのもの** を Polaris OpenStack 上に構築する root。

`idp/` が「Authentik に何を設定するか」なら、ここは「Authentik をどこで動かすか」。

## 何を作るか

Polaris（Kolla-Ansible OpenStack、Magnum/Octavia なし）にはマネージド
Kubernetes 基盤が無いため、**単一 VM + Docker Compose** で最小構成を立てる。
`documents/terraform/17-production-runbook.md` の Helm ベース K8s デプロイは
将来の本番像であり、ここでは対象外。

| リソース | 内容 |
|---|---|
| `openstack_compute_instance_v2.authentik` | `rocky-10` / `m1.medium`(4GB/2vCPU) / boot-from-volume 40GB / `lc-dev-net` |
| `openstack_networking_secgroup_v2.authentik` + rules | 22 / 9000 / 9443 / ICMP を許可 |
| `openstack_networking_floatingip_v2` + associate | `ext-net`（192.168.1.0/24）から採番 |
| `data.openstack_compute_keypair_v2.authentik` | 既存 keypair `authentik-idp` を参照のみ（下記「keypair について」参照） |
| `random_*` | `AUTHENTIK_SECRET_KEY` / postgres パスワード / akadmin パスワード / API トークンを新規生成 |

### keypair について（実機確認・2026-09-04）

当初は `tls_private_key` + `openstack_compute_keypair_v2`（resource）で新規生成する
設計だったが、`tls_private_key` は `terraform import` に対応していない。
既に存在する keypair `authentik-idp` と秘密鍵ファイル（`.ssh/authentik_idp`、
gitignore 済み・SSH に使用中）を安全に管理下へ移す手段が無かったため、
keypair は `data` 参照のみに変更した。誤って `resource` に戻して apply すると、
新しい鍵で keypair を作り直そうとして（`public_key` は変更不可のため
force-replace になり）既存 VM への SSH 経路を壊す。秘密鍵ファイル自体は
Terraform 管理外だが、既にあるものをそのまま使い続けられる。

> **本番 Ceph RGW backend への適用時の注意**: VM を最初に作った時点の本番
> state には `tls_private_key.authentik`/`openstack_compute_keypair_v2.authentik`
> が **resource として**（今の `data` 参照ではなく）記録されている。
> 本番 backend に対してこのコード（`data` 参照版）を初めて apply すると、
> Terraform は「config から消えた resource」とみなしてこの2つを
> **destroy しようとする**（tls_private_key 自体は消えても実害無いが、
> keypair の destroy は実際の SSH 経路を壊しかねない）。適用前に本番 state から
> `terraform state rm` でこの2つを外しておくこと:
> `terraform state rm tls_private_key.authentik openstack_compute_keypair_v2.authentik`

cloud-init が Docker をインストールし、`local/authentik/docker-compose.yml` を
忠実移植した構成（**server + worker + postgresql、Redis なし**。ローカルで
8日以上 healthy 稼働の実績構成）を `/opt/authentik/` に展開して起動する。
差分は `restart: unless-stopped` の付与のみ（VM 再起動で自動復帰）。

## 前提

- `local/clouds.yaml` に lc-dev スコープの cloud エントリ（既定 `polaris-admin`）。
  App credential は project 越境不可のため admin パスワード認証を使う。
  出所は `local/polaris-access.md`。
- 本番 state バックエンドは Ceph RGW（S3 互換）。認証情報は GitHub Secrets
  （`CEPH_RGW_ENDPOINT`/`CEPH_ACCESS_KEY_ID`/`CEPH_SECRET_ACCESS_KEY`）のみが
  持っており、ローカル開発機には無い想定。ローカルで動作確認・apply したい
  場合は下記の通り `backend_override.tf` でローカル state に切り替える。

## ローカル state での動作確認（本番 backend が使えない場合）

```bash
cat > backend_override.tf << 'EOF'
terraform {
  backend "local" {}
}
EOF
```

`*_override.tf` は `.gitignore` 済み。本番 state（Ceph RGW 上の実際に apply
済みの state）とは完全に別物になるので、**既に実在する VM 等を対象にする場合は
先に `terraform import` で現況を取り込んでから使うこと**（新規 apply すると
重複リソースを作ってしまう）。実機確認済み（2026-09-04）のインポート手順:

```bash
# 実際の値は openstack CLI・SSH で調べたものに置き換える
terraform import random_password.postgres <実際の POSTGRES_PASSWORD>
terraform import random_password.secret_key <実際の AUTHENTIK_SECRET_KEY>
terraform import random_password.bootstrap_password <実際の AUTHENTIK_BOOTSTRAP_PASSWORD>
terraform import random_id.bootstrap_token <AUTHENTIK_BOOTSTRAP_TOKEN の hex を base64url(no pad) に変換した値>
terraform import openstack_networking_secgroup_v2.authentik <secgroup id>
terraform import openstack_networking_secgroup_rule_v2.ssh <rule id>            # 22
terraform import openstack_networking_secgroup_rule_v2.authentik_http <rule id> # 9000
terraform import openstack_networking_secgroup_rule_v2.authentik_https <rule id> # 9443
terraform import openstack_networking_secgroup_rule_v2.icmp <rule id>
terraform import openstack_networking_port_v2.authentik <port id>
terraform import openstack_networking_floatingip_v2.authentik <floating ip の id（IP アドレスではない）>
terraform import openstack_networking_floatingip_associate_v2.authentik <floating ip の id>  # port id との連結ではなく floating ip の id 単体
terraform import openstack_compute_instance_v2.authentik <server id>
```

import 後、`terraform plan` は以下の理由でそのままだと差分が出る
（いずれも import が正しく復元できない・実質的に無害な項目）:

- **`random_password` の `special`**: import は常に `special=true` で
  復元するため、`secrets.tf` の `special=false` と食い違い「置き換え」判定
  になる。ローカル state の JSON を直接編集して `"special": true` を
  `"special": false` に修正する。
- **`openstack_compute_instance_v2` の `network[].port`**: import はこの
  フィールドを空文字のまま復元し、config の `port = ...` が
  force-replace 扱いになる。同じく state の JSON を直接編集して実際の
  port id を入れる。
- **`openstack_networking_port_v2` の `security_group_ids`/`fixed_ip`**: import
  はこれらを復元しないため in-place update が走るが、`fixed_ip` を変更しようと
  すると Neutron が「Floating IP に紐づいた fixed_ip は変更できない」と
  400 を返す（実害は無い apply エラー）。エラー後に `terraform plan` を
  取り直すと（apply 中の refresh で）解消していることを確認済み。

## 使い方

```bash
export OS_CLIENT_CONFIG_FILE="$(git rev-parse --show-toplevel)/local/clouds.yaml"
# 本番 Ceph RGW backend を使う場合（CI と同じ）
export AWS_ENDPOINT_URL_S3=<CEPH_RGW_ENDPOINT>
export AWS_ACCESS_KEY_ID=<CEPH_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<CEPH_SECRET_ACCESS_KEY>
export AWS_DEFAULT_REGION=us-east-1
# ローカル state で動作確認する場合は上記の代わりに backend_override.tf を使う

cd terraform/platform/infra/idp-infra
terraform init
terraform apply

# 出力（idp/ に渡す値）
terraform output -raw authentik_url            # http://<FIP>:9000
terraform output -raw authentik_token          # akadmin API トークン
terraform output -raw authentik_akadmin_password
```

初回 apply 後、cloud-init が Docker pull → compose up するまで数分かかる。

```bash
FIP=$(terraform output -raw floating_ip)
ssh -i .ssh/authentik_idp rocky@$FIP 'sudo cat /opt/authentik/.bootstrapped; sudo docker compose -f /opt/authentik/docker-compose.yml ps'
curl -fsS http://$FIP:9000/-/health/ready/ && echo OK
```

## idp/ からの接続

`terraform/platform/idp/` 側で:

```bash
export TF_VAR_authentik_url="$(cd ../infra/idp-infra && terraform output -raw authentik_url)"
export TF_VAR_authentik_token="$(cd ../infra/idp-infra && terraform output -raw authentik_token)"
cd ../idp
terraform plan
```

`idp/` は `authentik_url`/`authentik_token` の向き先を変数で切り替えるだけの
単一 state で、環境ごとに固定の state を持たない。ローカル開発 Authentik
（`local/authentik/`、`localhost:9000`）と Polaris インスタンス（本節）を
同じ state で交互に向き先を変えると、ブランド・シークレット等の値が食い違って
apply のたびに大量の diff が出る。両方を同時に永続運用したい場合は
`terraform workspace` か別 backend key で state を分けること。

> **重要（2026-09-04）**: Polaris の実 Authentik への `idp/` 初回適用
> （flow/stage/policy 一式・SMTP・GitHub/Discord Source、計 70+ リソース）は
> 本番の Ceph RGW backend ではなく、`idp/` 側にも同様の `backend_override.tf`
> を作ってローカル state で実施した（本番 backend の認証情報がこの検証環境に
> 無いため）。**つまり実際の Authentik には反映済みだが、本番 Ceph RGW 上の
> state はこれらのリソースをまだ一切知らない。** 次に CI（本番 backend）から
> `idp/` を apply すると、空の state から全リソースを作ろうとして
> 「既に存在する」エラーになるか、意図せず重複作成される。本番運用に載せる
> 前に、ローカルで作った state を Ceph RGW 側へ移す（`terraform state push`
> 等）か、同じ手順で改めて import し直す必要がある。

## VM の作り直し

`user_data`（cloud-init）は `ignore_changes` にしているため、テンプレートを
変えても自動では作り直さない。作り直すときは明示的に:

```bash
terraform taint openstack_compute_instance_v2.authentik
terraform apply
```

postgres データは VM 内の docker named volume `pg_data` にあり、VM 作り直しで
消える。恒久運用が必要になったら Cinder ボリュームを別途アタッチする構成へ。
