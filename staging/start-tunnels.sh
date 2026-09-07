#!/usr/bin/env bash
# staging の各サービスへトンネルを張る。
#
# dns_zone を設定して公開している場合、Authentik / infra-api / Harbor は
# ブラウザから直接 HTTPS で開けるので、このスクリプトは要りません。
# 公開していないとき、または公開しているサービスを手元から直接叩きたいときに使います。
#
# ポートは local/gcp-devstack/start-tunnels.sh（18080/18081/1080）と重ならないよう
# 28000 番台にしています。local と staging を同時に開けるようにするためです。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/gcp"

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

PROJECT_ID="$(tf_out project_id)"
ZONE="$(tf_out zone)"
DEVSTACK="$(tf_out devstack_instance_name)"
PLATFORM="$(tf_out platform_instance_name)"

pids=()

# VM のネットワークインタフェースで待ち受けているものは IAP トンネルで届く
tunnel() { # tunnel <instance> <remote-port> <local-port> <label>
  echo "$4: http://localhost:$3/"
  gcloud compute start-iap-tunnel "$1" "$2" \
    --local-host-port="localhost:$3" \
    --project="$PROJECT_ID" --zone="$ZONE" &
  pids+=("$!")
}

# 127.0.0.1 にしか bind していないものは IAP トンネルでは届かない
# （IAP は VM のインタフェースに着くため）。SSH のローカルフォワードは
# VM の中から 127.0.0.1 へ繋ぐので届く
ssh_forward() { # ssh_forward <instance> <remote-port> <local-port> <label>
  echo "$4: http://localhost:$3/"
  gcloud compute ssh "$1" --tunnel-through-iap --zone="$ZONE" --project="$PROJECT_ID" \
    -- -N -L "$3:127.0.0.1:$2" &
  pids+=("$!")
}

tunnel      "$DEVSTACK" 80   28080 "OpenStack API / Horizon"
tunnel      "$PLATFORM" 9000 29000 "Authentik"
tunnel      "$PLATFORM" 8080 28081 "Harbor"
ssh_forward "$PLATFORM" 8081 28001 "lcn-infra-api（Caddy を通さない直行。認証は同じ）"

# DevStack のサービスカタログは SERVICE_HOST を全エンドポイントのベース URL として
# 返します。公開していない構成ではそれが VM の内部 IP なので、固定ポートの
# ポートフォワードでは届きません。SOCKS5 プロキシを併用してください。
#   export ALL_PROXY=socks5h://localhost:1081
#   export NO_PROXY=localhost,127.0.0.1
#
# 公開している構成（devstack_allowed_source_ranges を設定）では、カタログが
# openstack.<zone> を返すため、許可 CIDR からなら直接届きます。プロキシは不要です。
echo "SOCKS5 プロキシ: socks5h://localhost:1081"
gcloud compute ssh "$DEVSTACK" \
  --tunnel-through-iap --zone="$ZONE" --project="$PROJECT_ID" -- -N -D 1081 &
pids+=("$!")

echo ""
echo "停止するには Ctrl-C するか、上記の PID を kill してください"
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
wait
