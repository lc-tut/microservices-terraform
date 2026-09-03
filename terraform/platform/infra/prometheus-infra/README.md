# terraform/platform/infra/prometheus-infra

Prometheus + `openstack-exporter` を単一 VM + Docker Compose で構築する root。
元々は `terraform/platform/infra/cloudkitty-infra/` に同居していたが、
CloudKitty 専用にせず他の監視用途にも再利用しやすくするために分離した。

`openstack-exporter` は OpenStack API を読み取り専用で叩いてメトリクス化し、
Prometheus がそれをスクレイプする。CloudKitty 向けに、`tenant_id` ラベルを
`project_id` へ正規化し 1 プロジェクト 1 系列へ集約する recording rule
（`cloudkitty:*`）も同梱している——CloudKitty の prometheus collector は
`<metric>{project_id="<id>"}[<period>s]` という固定形のクエリしか組み立てられない
（`label_replace` 等を差し込めない）ため、この正規化層が必須。

## 前提

- `local/clouds.yaml` に対象プロジェクトへスコープされた cloud エントリ
  （`infra/cloudkitty-infra` と同じもの）。
- `var.keystone_auth_url` / `var.os_admin_password` はデフォルト値を置いていない。
  apply 時に明示的に渡す（`infra/cloudkitty-infra/README.md` の「デプロイ」節参照）。

> **本番 Ceph RGW backend への適用時の注意**: この VM は `backend_override.tf`
> によるローカル state で新規作成した（本番 backend の認証情報がこの検証環境に
> 無いため）。本番 backend 側の state はまだ空のまま。空の状態で CI から
> apply すると、既存の実 VM とは別に**新規 VM を重複して作ってしまう**。
> 本番運用に載せる前に、ローカルで作った state を本番 backend へ移す
> （`terraform state push` 等）こと。

## デプロイ

```bash
export OS_CLIENT_CONFIG_FILE="$(git rev-parse --show-toplevel)/local/clouds.yaml"
export AWS_ENDPOINT_URL_S3=http://localhost:19000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1

cd terraform/platform/infra/prometheus-infra
terraform init && terraform apply \
  -var="keystone_auth_url=http://<host>:5000/v3" \
  -var="os_admin_password=<password>"

terraform output -raw prometheus_url   # → infra/cloudkitty-infra の var.prometheus_url に渡す
```

## 動作確認

```bash
FIP=$(terraform output -raw floating_ip)
ssh -i .ssh/prometheus rocky@$FIP 'cat /opt/prometheus/.bootstrapped; docker compose -f /opt/prometheus/docker-compose.yml ps'
curl -fsS "http://$FIP:9090/-/healthy" && echo OK
curl -s "http://$FIP:9090/api/v1/query?query=cloudkitty:vcpu:used" | python3 -m json.tool
```

## 既知の制約

- **exporter は 2.0.0-alpha を使用**。1.7.0(最新 stable)・1.8.0-alpha は cinder
  メトリクス（`limits_volume_used_gb`）が無く、CloudKitty 側の volume 課金が動かない。
  alpha 版のため一部エンドポイント（VPN / security-group 系）に 404 の ERROR ログが
  出るが、必要なメトリクスの取得には影響しない。
- `var.os_admin_password` はパスワード直書き。将来は読み取り専用のサービス
  ユーザー + application credential に置き換える。

## 実機で判明した罠（2026-09-04）

- **ホストの 9090 番ポートは Rocky Linux の `cockpit.socket`（Web コンソール）が
  既定で掴んでいる**。Prometheus は `ports: ["9090:9090"]` でホストに公開する
  設計（同一 VM に同居していた旧構成の `expose`（コンテナ内限定）とは違い、
  別 VM の CloudKitty から到達できる必要があるため）なので、必ず
  `systemctl disable --now cockpit.socket` で先に明け渡す。cloud-init の
  runcmd に組み込み済み（`templates/cloud-init.yaml.tftpl`）。
- **`docker compose restart` だけではポート公開が復活しないことがある**:
  cockpit との競合で最初の起動時にポート bind に失敗すると、その後
  `restart` を繰り返しても `docker inspect` の `NetworkSettings.Ports` が
  空のままになるケースを実機で確認した（`docker-proxy` プロセスが立たない）。
  `docker compose down && docker compose up -d`（コンテナとネットワークを
  作り直す）まで行うと解消する。
- 上記2点を踏まえ、初回 apply 後に外部から `curl http://<FIP>:9090/-/healthy`
  が失敗する場合は、まず `systemctl status cockpit.socket` を確認し、
  有効なら無効化してから `docker compose -f /opt/prometheus/docker-compose.yml
  down && ... up -d` を実行する。
