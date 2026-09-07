#!/usr/bin/env bash
# staging の各サービスへ IAP トンネルを張る。
# ファイアウォールが IAP レンジのみ許可のため、手元から触るには毎回これが要る。
#
# ポートは local/gcp-devstack/start-tunnels.sh（18080/18081/1080）と重ならないよう
# 28000 番台にしている。local と staging を同時に開けるようにするため。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/gcp"

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

PROJECT_ID="$(tf_out project_id)"
ZONE="$(tf_out zone)"
DEVSTACK="$(tf_out devstack_instance_name)"
PLATFORM="$(tf_out platform_instance_name)"

pids=()
tunnel() { # tunnel <instance> <remote-port> <local-port> <label>
  echo "$4: http://localhost:$3/"
  gcloud compute start-iap-tunnel "$1" "$2" \
    --local-host-port="localhost:$3" \
    --project="$PROJECT_ID" --zone="$ZONE" &
  pids+=("$!")
}

tunnel "$DEVSTACK" 80   28080 "OpenStack API / Horizon"
tunnel "$PLATFORM" 9000 29000 "Authentik"
tunnel "$PLATFORM" 8080 28081 "Harbor"
tunnel "$PLATFORM" 80   28000 "ingress-nginx (Middleware API / SPA)"

# DevStack のサービスカタログは HOST_IP（VM の内部 IP）を全エンドポイントの
# ベース URL として返すため、openstack CLI と Terraform の openstack プロバイダーは
# トークン発行以外のほぼ全ての操作でその IP へ直接アクセスしようとする。
# 固定ポートのポートフォワードでは届かないので SOCKS5 プロキシを併用する。
#   export ALL_PROXY=socks5h://localhost:1081
#   export NO_PROXY=localhost,127.0.0.1
# （platform VM の k3s は同じ VPC にいるためプロキシ無しで直接届く。
#   これが要るのは手元から叩くときだけ）
echo "SOCKS5 プロキシ: socks5h://localhost:1081"
gcloud compute ssh "$DEVSTACK" \
  --tunnel-through-iap --zone="$ZONE" --project="$PROJECT_ID" -- -N -D 1081 &
pids+=("$!")

echo ""
echo "停止するには Ctrl-C するか、上記の PID を kill してください"
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
wait
