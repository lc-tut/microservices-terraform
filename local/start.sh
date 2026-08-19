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

echo "=== LocalStack 起動（S3 バックエンド） ==="
docker start localstack 2>/dev/null || docker run -d \
  --name localstack \
  -p 4566:4566 \
  -e SERVICES=s3 \
  localstack/localstack

# LocalStack の S3 が ready になるまで待つ（最大 30 秒）
echo "  LocalStack 待機中..."
for i in $(seq 1 15); do
  if docker exec localstack awslocal s3 ls >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
# tfstate バケットが未作成なら作成
docker exec localstack awslocal s3 mb s3://linuxclub-tfstate \
  --region us-east-1 2>/dev/null || true
echo "  tfstate バケット: s3://linuxclub-tfstate (LocalStack)"

echo "=== kind クラスター確認 ==="
kind get clusters 2>/dev/null | grep -q lc-local \
  || kind create cluster --name lc-local

echo ""
echo "起動完了"
echo "  Authentik : http://localhost:9000/if/flow/initial-setup/ (初回のみ)"
echo "  Authentik : http://localhost:9000/if/admin/"
echo "  LocalStack: http://localhost:4566  (S3 バックエンド)"
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
