# terraform/platform/infra/harbor-infra

Harbor（コンテナレジストリ）を単一 VM + 公式 online installer（`install.sh`）で構築する root。

`idp-infra`・`cloudkitty-infra`・`prometheus-infra` は docker-compose.yml を
自前で書いているが、Harbor は core/jobservice/registry/registryctl/portal/
redis/postgresql（+ trivy）の依存関係が複雑で、公式インストーラの `prepare`
スクリプトが生成する構成に素直に従う方が壊れにくいため、ここだけ方式を変えている。
`harbor.yml` だけを Terraform でテンプレート化し、`install.sh` に生成・起動を任せる。

**実機適用 ✅ 完了（2026-09-04）**: 実機 Polaris に `backend_override.tf` の
ローカル state で apply 済み。README 記載の「Floating IP 確定 → 再 apply」の
2段階手順どおりに問題なく完了し、`install.sh` 一発で core/db/jobservice/log/
portal/nginx/redis/registry/registryctl/trivy-adapter の全10コンテナが
`healthy` になった（実機で判明した罠は特に無し）。`GET /api/v2.0/systeminfo`・
`GET /api/v2.0/projects`（デフォルトの `library` プロジェクトが admin 所有で
作成済み）で疎通確認済み。`docker login` は本 README の「既知の制約」どおり、
クライアント側に `insecure-registries` を設定しないと TLS ハンドシェイクで
失敗する（未設定の状態で確認済み）。

## 前提

- `local/clouds.yaml` に対象プロジェクトへスコープされた cloud エントリ
  （`idp-infra` 等と同じもの）。
- `var.harbor_hostname` はデフォルト値を置いていない。VM の Floating IP は
  apply するまで確定しないため、初回 apply 後に `terraform output floating_ip`
  で判明したアドレスを渡して再 apply するか、あらかじめ確保済みの
  Floating IP / DNS 名があればそれを渡す（下記「デプロイ」参照）。

> **本番 Ceph RGW backend への適用時の注意**: この VM は `backend_override.tf`
> によるローカル state で新規作成する想定（本番 backend の認証情報がこの検証環境に
> 無いため）。本番 backend 側の state はまだ空のまま。空の状態で CI から
> apply すると、既存の実 VM とは別に**新規 VM を重複して作ってしまう**。
> 本番運用に載せる前に、ローカルで作った state を本番 backend へ移す
> （`terraform state push` 等）こと。

## デプロイ

Floating IP が未確定の1回目は仮のホスト名で apply し、判明したアドレスで
2回目を apply する（`user_data` は `lifecycle.ignore_changes` に入っているため、
ホスト名を変えて再適用したい場合は `terraform apply -replace=openstack_compute_instance_v2.harbor`
が必要）。

```bash
export OS_CLIENT_CONFIG_FILE="$(git rev-parse --show-toplevel)/local/clouds.yaml"
export AWS_ENDPOINT_URL_S3=http://localhost:19000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1

cd terraform/platform/infra/harbor-infra
terraform init

# 1回目: Floating IP 確定のため仮のホスト名で apply
terraform apply -var="harbor_hostname=harbor.invalid"
FIP=$(terraform output -raw floating_ip)

# 2回目: 確定した Floating IP で作り直す
terraform apply -var="harbor_hostname=${FIP}" -replace=openstack_compute_instance_v2.harbor

terraform output -raw harbor_admin_password   # GitHub Secrets の HARBOR_ADMIN_PASSWORD に登録
```

## 動作確認

```bash
FIP=$(terraform output -raw floating_ip)
ssh -i .ssh/harbor rocky@$FIP 'cat /opt/harbor/.bootstrapped; docker compose -f /opt/harbor/docker-compose.yml ps'
curl -fsS "http://$FIP/api/v2.0/systeminfo" && echo OK

# docker login（HTTP のみで TLS 未設定のため insecure-registries への追加が必要。後述）
docker login "$FIP" -u admin -p "$(terraform output -raw harbor_admin_password)"
```

## 既知の制約

- **HTTP のみ**。TLS 証明書の発行・設定はこの root ではやらない
  （`idp-infra`・`cloudkitty-infra`・`prometheus-infra` も同様に HTTP 直公開）。
  外部公開・TLS 終端は `16-implementation-phases.md` の Phase 9（共有 Ingress
  Controller + Octavia LB）で扱う想定。それまでは docker クライアント側の
  `/etc/docker/daemon.json` に `"insecure-registries": ["<FIP>"]` を追加する
  必要がある。
- `harbor_hostname` は Floating IP 確定後の再 apply が前提（上記「デプロイ」参照）。
  DNS（Phase 8）が使えるようになったら、Floating IP ではなく DNS 名に切り替える。
- `harbor_version`（既定 `v2.13.1`）・`harbor_with_trivy`（既定 `true`）は
  `variables.tf` で変更可能。online installer はコンテナイメージ自体を
  実行時に pull するため、インストーラ本体のダウンロードは軽いが、初回
  `install.sh` はイメージ pull 分の時間がかかる。
- Harbor 内蔵の PostgreSQL・Redis はコンテナ内で完結し、外部には公開しない
  （`cloudkitty-infra` のように別 VM の Prometheus 等と連携する必要が無いため）。
- プロジェクトごとの Harbor Project（レジストリ上の名前空間）作成は
  この root の範囲外。`catalog/projects/` から Harbor Terraform provider
  （`goharbor/harbor`）経由で作る想定（未実装）。
