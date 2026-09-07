# staging 環境

`local/` が「各自の手元にひとつずつ建てる開発環境」なのに対し、
`staging/` は **全員が同じ1組を共有する検証環境**です。GCP 上に
OpenStack(DevStack)・Authentik・Harbor・Kubernetes(k3s) を建て、
`terraform/platform/` 配下のコードと Middleware API
(`lcn-infra-api` / `lcn-billing-api`) を本番に近い形で動かします。

- 手元だけで完結する動作確認 → [`../documents/terraform/15-local-development.md`](../documents/terraform/15-local-development.md)
- 本番をゼロから建てる → [`../documents/terraform/17-production-runbook.md`](../documents/terraform/17-production-runbook.md)

---

## 構成

```text
                        IAP トンネル（22 / 80 / 443 / 8080 / 9000）
                                   │
   ┌───────────────────────────────┴───────────────────────────────┐
   │  VPC: lc-staging  (10.20.0.0/24, asia-northeast1-a)           │
   │                                                               │
   │  lc-staging-devstack  10.20.0.10   n2-highmem-4 (4vCPU/32GB)  │
   │    DevStack (stable/2026.1)                                   │
   │      Keystone / Nova / Neutron / Glance / Placement / Horizon  │
   │      Cinder / Swift / CloudKitty(Ceilometer+Gnocchi) / Trove   │
   │                                                               │
   │  lc-staging-platform  10.20.0.11   e2-standard-4 (4vCPU/16GB) │
   │    Docker Compose                                             │
   │      Authentik            :9000                               │
   │      Harbor               :8080                               │
   │    k3s（traefik 無効 / ingress-nginx / NetworkPolicy 有効）    │
   │      lc-platform ns: Authentik Outpost / lcn-infra-api /       │
   │                      lcn-billing-api / Postgres                │
   └───────────────────────────────────────────────────────────────┘
```

インターネットには何も公開していません。外部 IP は付いていますが、
ファイアウォールが IAP レンジ（`35.235.240.0/20`）のみ許可しているため、
到達経路は IAP トンネルだけです。

### なぜ VM を2台に分けているか

DevStack のクリーン構築は 40 分前後かかります。1台に同居させると、
DevStack を作り直すたびに Authentik と Middleware API まで巻き込んで
落ちます。`n2-standard-8` 1台と `n2-highmem-4` + `e2-standard-4` 2台では
計算費がほぼ同額なので、分割による割高はディスクと外部 IP のぶん
（月 1,600 円程度）だけです。

### なぜ Harbor が platform VM 側にあるか

`local/gcp-devstack/` では DevStack と同じ VM に入れていますが、staging では
platform VM に置いています。DevStack は作り直す前提のものなので、
そこに置くとイメージレジストリが毎回消えるためです。

---

## 1. 構築

```bash
gcloud auth login
gcloud auth application-default login

cd staging/gcp
cp terraform.tfvars.example terraform.tfvars
# project_id / devstack_admin_password / iap_tunnel_users を入力する

terraform init
terraform plan
terraform apply
```

state は本番と同じ GCS バケット（`linuxclub-network-cloud-terraform-state`、
プロジェクト `main-vcompute`）の `tfstate/staging/gcp` に置きます。
全員が同じ1組を共有するので、ロックが効くリモートに置いています。

初回ブートで startup-script が動きます。**DevStack 側は 20〜40 分、
platform 側は 10〜15 分**かかります（Harbor を入れない場合は platform 側が
5 分程度）。進捗はどちらも VM 上の `/var/log/lc-staging-bootstrap.log` です。

```bash
gcloud compute ssh lc-staging-devstack --tunnel-through-iap \
  --zone=asia-northeast1-a --command="tail -f /var/log/lc-staging-bootstrap.log"
```

> IAP トンネルを使うには自分の GCP アカウントに
> `roles/iap.tunnelResourceAccessor` が要ります。`iap_tunnel_users` に
> 入れて apply すれば Terraform が付与します。

### 認証情報の取り出し

Authentik と Harbor のパスワードは、`terraform.tfvars` で明示しなければ
Terraform が生成して state に持ちます。

```bash
terraform -chdir=staging/gcp output -json credentials | jq
```

`authentik_api_token` は `terraform/platform/idp/` を staging に向けて
apply するときの `AUTHENTIK_TOKEN` です。

---

## 2. 接続

```bash
./staging/start-tunnels.sh
```

| サービス | URL |
| --- | --- |
| OpenStack API / Horizon | <http://localhost:28080/> |
| Keystone | <http://localhost:28080/identity/> |
| Authentik | <http://localhost:29000/if/admin/> |
| Harbor | <http://localhost:28081/> |
| ingress-nginx（Middleware API・SPA） | <http://localhost:28000/> |

ポートを 28000 番台にしているのは、`local/gcp-devstack/`（18080 / 18081 / 1080）と
同時に開けるようにするためです。

### openstack CLI / Terraform から使うとき

DevStack のサービスカタログは `HOST_IP`（VM の内部 IP `10.20.0.10`）を
全エンドポイントのベース URL として返します。固定ポートのポートフォワードでは
届かないので、`start-tunnels.sh` が張る SOCKS5 プロキシを併用します。

```bash
export ALL_PROXY=socks5h://localhost:1081
export NO_PROXY=localhost,127.0.0.1
export OS_CLIENT_CONFIG_FILE="$PWD/staging/clouds.yaml"   # 下記で作る
export OS_CLOUD=lc-staging
```

`staging/clouds.yaml`（`.gitignore` 済み）:

```yaml
clouds:
  lc-staging:
    auth:
      auth_url: http://localhost:28080/identity/
      application_credential_id: "<app-cred-id>"
      application_credential_secret: "<app-cred-secret>"
    auth_type: v3applicationcredential
    region_name: RegionOne
    interface: public
```

Application Credential の発行は `local/issue-appcred.sh` と同じ手順です。

> platform VM の k3s は同じ VPC にいるため、プロキシ無しで
> `http://10.20.0.10/identity/` に直接届きます。プロキシが要るのは
> 手元から叩くときだけです。

---

## 3. 停止・破棄

VM は **IAP トンネル（SSH）が 45 分途切れると自動で停止します**。
staging へのアクセスは全て IAP トンネル越しなので、トンネルが1本も無い＝
誰も使っていない、と判断できます。`stack.sh` の実行中は停止しません。
長時間の作業を明示的に守るには VM 上で `sudo touch /run/no-idle-shutdown`
します（解除は `rm`）。

```bash
# 手動で止める / 起こす
gcloud compute instances stop  lc-staging-devstack lc-staging-platform \
  --zone=asia-northeast1-a
gcloud compute instances start lc-staging-devstack lc-staging-platform \
  --zone=asia-northeast1-a
```

**止めるだけではディスク代が残ります**（150GB + 50GB の pd-balanced で
月 4,144 円）。しばらく使わないなら破棄してください。

```bash
terraform -chdir=staging/gcp destroy
```

外部 IP は静的に取らずエフェメラルにしてあるので、VM を止めている間の
IP 課金はありません（静的 IP は停止中も月 1,745 円/個かかります）。

---

## 費用（asia-northeast1・税別・2026-09 時点の Cloud Billing Catalog 実価格）

| | 24時間 | 3日間(72h) | 平日8h/日(176h) | 24/7(730h) |
| --- | ---: | ---: | ---: | ---: |
| devstack (n2-highmem-4, 150GB) | ¥1,406 | ¥4,218 | ¥13,994 | ¥42,767 |
| platform (e2-standard-4, 50GB) | ¥744 | ¥2,231 | ¥7,564 | ¥22,621 |
| **合計** | **¥2,150** | **¥6,449** | **¥21,558** | **¥65,388** |

3日間の欄は「作って3日使って `destroy` する」前提でディスクも 72 時間分だけ
数えています。停止したまま残すとディスク代（月 4,144 円）が乗り続けます。

DevStack VM のスペックを変えた場合（24/7・ディスクと IP 込み）:

| | 24/7 | 平日8h/日 |
| --- | ---: | ---: |
| n2-standard-4 (4vCPU/16GB, 100GB) — local と同一 | ¥31,644 | ¥10,526 |
| **n2-highmem-4 (4vCPU/32GB, 150GB) — 既定** | ¥42,767 | ¥13,994 |
| n2-standard-8 (8vCPU/32GB, 150GB) | ¥61,670 | ¥18,551 |

DevStack で先に詰まるのは CPU ではなく RAM（Nova のゲスト VM に加えて
Trove・CloudKitty・Gnocchi が常駐する）ため、既定は vCPU を local と同じ 4 のまま
メモリだけ倍にした `n2-highmem-4` にしています。

---

## 既知の落とし穴

DevStack 側は `local/gcp-devstack/` と同じ構成なので、そこで踏んだ問題は
そのまま起きます。対処は
[`../documents/terraform/15-local-development.md`](../documents/terraform/15-local-development.md)
の「`stack.sh` が途中で終わったあとの復旧」にまとまっています。特に:

- `stack.sh` は**失敗しても再実行してはいけない**。`unstack.sh` + `clean.sh`
  からやり直す
- 再構築の前に `/opt/stack/horizon/openstack_dashboard/enabled/_32*.py` と
  `/opt/stack/async` を消す
