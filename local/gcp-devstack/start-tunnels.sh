#!/usr/bin/env bash
# OpenStack API/Horizon(80) と Harbor(8080) への IAP トンネルをバックグラウンドで張る。
# ファイアウォールが IAP レンジのみ許可のため、ローカルからアクセスするには
# 毎回このトンネルを張る必要がある（WSL からも Windows からも同じスクリプトで動く）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/windows-autostop/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config.env が見つかりません: $CONFIG_FILE" >&2
  echo "windows-autostop/config.env.example をコピーして terraform output の値を入力してください" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${PROJECT_ID:?config.env に PROJECT_ID を設定してください}"
: "${ZONE:?config.env に ZONE を設定してください}"
: "${INSTANCE_NAME:?config.env に INSTANCE_NAME を設定してください}"

echo "OpenStack API/Horizon: http://localhost:18080/ にトンネル中..."
gcloud compute start-iap-tunnel "$INSTANCE_NAME" 80 \
  --local-host-port=localhost:18080 \
  --project="$PROJECT_ID" --zone="$ZONE" &
echo "  PID: $!"

echo "Harbor: http://localhost:18081/ にトンネル中..."
gcloud compute start-iap-tunnel "$INSTANCE_NAME" 8080 \
  --local-host-port=localhost:18081 \
  --project="$PROJECT_ID" --zone="$ZONE" &
echo "  PID: $!"

# DevStack のサービスカタログは HOST_IP（VM 内部プライベート IP、例: 10.10.0.2）を
# 全エンドポイントのベース URL として返すため、openstack CLI / Terraform の
# openstack プロバイダーは token issue 以外ほぼ全ての操作でこの IP に直接
# アクセスしようとする。IAP トンネル（固定ポートのポートフォワードのみ）では
# 届かないため、SSH の SOCKS5 プロキシ（IAP 経由）を別途張る。
# 使う側は ALL_PROXY=socks5h://localhost:1080 と
# NO_PROXY=localhost,127.0.0.1 を設定すること
# （詳細: documents/terraform/15-local-development.md の
# 「SOCKS5 プロキシ（サービスカタログ越しのアクセスに必須）」）
echo "SOCKS5 プロキシ (localhost:1080) を起動中..."
gcloud compute ssh "$INSTANCE_NAME" \
  --tunnel-through-iap --zone="$ZONE" -- -N -D 1080 &
echo "  PID: $!"

echo ""
echo "停止するには上記 PID を kill するか、このスクリプトを実行したシェルを閉じてください"
wait
