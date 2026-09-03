# terraform/platform/idp-infra

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
| `openstack_compute_keypair_v2` + `tls_private_key` | 秘密鍵は `.ssh/authentik_idp`（gitignore 済み） |
| `random_*` | `AUTHENTIK_SECRET_KEY` / postgres パスワード / akadmin パスワード / API トークンを新規生成 |

cloud-init が Docker をインストールし、`local/authentik/docker-compose.yml` を
忠実移植した構成（**server + worker + postgresql、Redis なし**。ローカルで
8日以上 healthy 稼働の実績構成）を `/opt/authentik/` に展開して起動する。
差分は `restart: unless-stopped` の付与のみ（VM 再起動で自動復帰）。

## 前提

- `local/clouds.yaml` に lc-dev スコープの cloud エントリ（既定 `polaris-admin`）。
  App credential は project 越境不可のため admin パスワード認証を使う。
  出所は `local/polaris-access.md`。
- state バックエンドは `terraform/platform/idp/` と同じローカル MinIO
  （`local/start.sh` で起動、`http://localhost:19000`）。key のみ別。

## 使い方

```bash
export OS_CLIENT_CONFIG_FILE="$(git rev-parse --show-toplevel)/local/clouds.yaml"
# MinIO backend（local/start.sh で起動済みなら）
export AWS_ENDPOINT_URL_S3=http://localhost:19000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1

cd terraform/platform/idp-infra
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
export TF_VAR_authentik_url="$(cd ../idp-infra && terraform output -raw authentik_url)"
export TF_VAR_authentik_token="$(cd ../idp-infra && terraform output -raw authentik_token)"
cd ../idp
terraform plan
```

`idp/` の state はローカル開発 Authentik（`localhost:9000`）向けに作られている
ため、Polaris インスタンスを別管理する場合は `terraform workspace` か別 backend
key で state を分けること（同一 state のまま向き先だけ変えると全リソースが
再作成扱いになる）。

## VM の作り直し

`user_data`（cloud-init）は `ignore_changes` にしているため、テンプレートを
変えても自動では作り直さない。作り直すときは明示的に:

```bash
terraform taint openstack_compute_instance_v2.authentik
terraform apply
```

postgres データは VM 内の docker named volume `pg_data` にあり、VM 作り直しで
消える。恒久運用が必要になったら Cinder ボリュームを別途アタッチする構成へ。
