#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Authentik 起動 ==="
if [ ! -f "$SCRIPT_DIR/authentik/.env" ]; then
  echo ".env が見つかりません。セットアップを実行します..."
  cp "$SCRIPT_DIR/authentik/.env.example" "$SCRIPT_DIR/authentik/.env"
  SECRET=$(openssl rand -base64 36 | tr -d '\n')
  sed -i "s/change-me-generate-with-openssl-rand-base64-36/$SECRET/" \
    "$SCRIPT_DIR/authentik/.env"
  BOOTSTRAP_PW=$(openssl rand -base64 24 | tr -d '\n')
  sed -i "s#change-me-generate-with-openssl-rand-base64-24#$BOOTSTRAP_PW#" \
    "$SCRIPT_DIR/authentik/.env"
  echo ".env を生成しました: $SCRIPT_DIR/authentik/.env"
  echo "akadmin の初期パスワードも自動生成しました（.env の AUTHENTIK_BOOTSTRAP_PASSWORD）"
fi
cd "$SCRIPT_DIR/authentik"
docker compose up -d
cd "$SCRIPT_DIR"

echo "=== MinIO 起動（S3 バックエンド） ==="
docker start minio-local 2>/dev/null || docker run -d \
  --name minio-local \
  -p 19000:9000 \
  -p 19001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data --console-address ":9001"

# MinIO が ready になるまで待つ（最大 30 秒）
echo "  MinIO 待機中..."
for i in $(seq 1 15); do
  if curl -sf http://localhost:19000/minio/health/live >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
# tfstate バケットが未作成なら作成
AWS_ACCESS_KEY_ID=minioadmin \
AWS_SECRET_ACCESS_KEY=minioadmin \
aws s3 mb s3://linuxclub-tfstate \
  --endpoint-url http://localhost:19000 \
  --region us-east-1 2>/dev/null || true
echo "  tfstate バケット: s3://linuxclub-tfstate (MinIO)"

echo "=== Vault 起動（dev モード） ==="
# Middleware API が実行時に per-project Application Credential を読む先。
# dev モードなのでデータはメモリ上のみ（コンテナを消すと消える）。
# 本番は 14-middleware-architecture.md のとおり Vault Agent サイドカー経由で読む
mkdir -p "$SCRIPT_DIR/vault"
if [ ! -f "$SCRIPT_DIR/vault/.env" ]; then
  VAULT_TOKEN_VALUE="$(openssl rand -hex 16)"
  printf 'VAULT_ADDR=http://localhost:8200\nVAULT_TOKEN=%s\n' "$VAULT_TOKEN_VALUE" \
    > "$SCRIPT_DIR/vault/.env"
  echo "  ルートトークンを生成しました: $SCRIPT_DIR/vault/.env"
fi
# shellcheck disable=SC1091
. "$SCRIPT_DIR/vault/.env"

docker start vault-local 2>/dev/null || docker run -d \
  --name vault-local \
  -p 8200:8200 \
  --cap-add=IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID="$VAULT_TOKEN" \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  hashicorp/vault

echo "  Vault 待機中..."
for i in $(seq 1 15); do
  if curl -sf http://localhost:8200/v1/sys/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# 14-middleware-architecture.md が前提にする kv-v2 を kv/ にマウントする
# （dev モードの既定は secret/ なので別途有効化する）
if ! docker exec -e VAULT_TOKEN="$VAULT_TOKEN" -e VAULT_ADDR=http://127.0.0.1:8200 \
     vault-local vault secrets list 2>/dev/null | grep -q '^kv/'; then
  docker exec -e VAULT_TOKEN="$VAULT_TOKEN" -e VAULT_ADDR=http://127.0.0.1:8200 \
    vault-local vault secrets enable -path=kv kv-v2 >/dev/null 2>&1 \
    && echo "  kv-v2 を kv/ にマウントしました"
fi

echo "=== kind クラスター確認 ==="
kind get clusters 2>/dev/null | grep -q lc-local \
  || kind create cluster --name lc-local

echo ""
echo "起動完了"
echo "  Authentik : http://localhost:9000/if/flow/initial-setup/ (初回のみ)"
echo "  Authentik : http://localhost:9000/if/admin/"
echo "  MinIO     : http://localhost:19000  (S3 API)"
echo "  MinIO UI  : http://localhost:19001  (コンソール — minioadmin/minioadmin)"
echo "  Vault     : http://localhost:8200   (dev。トークンは local/vault/.env)"
echo "  K8s       : kubectl --context kind-lc-local"
echo ""
echo "OpenStack (DevStack) / Harbor は GCP VM 上で稼働（local/gcp-devstack/）:"
echo "  VM が停止中なら起動:  ./gcp-devstack/windows-autostop/start-vm.sh"
echo "                        (Windows なら start-vm.ps1)"
echo "  IAP トンネルを開始:   ./gcp-devstack/start-tunnels.sh"
echo "  OpenStack : http://localhost:18080/identity/ (トンネル起動後)"
echo "  Harbor    : http://localhost:18081/           (トンネル起動後)"
echo ""
echo "OpenStack を使うには:"
echo "  export OS_CLIENT_CONFIG_FILE=\"$SCRIPT_DIR/clouds.yaml\""
echo "  export OS_CLOUD=gcp-devstack"
