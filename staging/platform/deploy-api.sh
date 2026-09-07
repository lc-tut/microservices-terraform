#!/usr/bin/env bash
# lcn-infra-api を staging の platform VM に配備する。
#
#   staging/platform/deploy-api.sh --repo ../lcn-infra-api
#
# やること:
#   1. 手元でコンテナイメージを構築する
#   2. VM へ運ぶ（Harbor があれば push、無ければ docker save | ssh docker load）
#   3. VM 上の .env に OpenStack のサービスアカウントを書き込む
#   4. migrate を流してから api / worker / reconciler を起動する
#
# イメージを CI で作っていないので、手元で構築して運んでいる。
# lcn-infra-api の CI がイメージを GHCR に push するようになったら、
# ここは pull に置き換えられる。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GCP_DIR="$REPO_ROOT/staging/gcp"

API_REPO="${API_REPO:-$REPO_ROOT/../lcn-infra-api}"
TAG="$(date +%Y%m%d-%H%M%S)"
OS_SERVICE_USERNAME="${OS_SERVICE_USERNAME:-admin}"
OS_SERVICE_PASSWORD="${OS_SERVICE_PASSWORD:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) API_REPO="$2"; shift 2 ;;
    --tag)  TAG="$2"; shift 2 ;;
    --os-username) OS_SERVICE_USERNAME="$2"; shift 2 ;;
    --os-password) OS_SERVICE_PASSWORD="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "不明な引数: $1" >&2; exit 1 ;;
  esac
done

[ -f "$API_REPO/Dockerfile" ] || {
  echo "lcn-infra-api のチェックアウトが見つかりません: $API_REPO" >&2
  echo "--repo でパスを指定してください" >&2
  exit 1
}

tfout() { terraform -chdir="$GCP_DIR" output -raw "$1" 2>/dev/null; }
tfjson() { terraform -chdir="$GCP_DIR" output -json "$1" 2>/dev/null || echo '{}'; }
field() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$2') or '')"; }

ZONE="$(tfout zone)"
PROJECT="$(tfout project_id)"
VM="$(tfout platform_instance_name)"
CREDS="$(tfjson credentials)"
URLS="$(tfjson urls)"

[ -n "$VM" ] || { echo "staging/gcp の output が読めません。先に apply してください" >&2; exit 1; }

# OpenStack のサービスアカウント。
# **staging は admin をそのまま使う。** 本番は ADR-0014 のとおり専用の
# サービスアカウントを作り、全 project に member を付けて使うこと。
if [ -z "$OS_SERVICE_PASSWORD" ]; then
  OS_SERVICE_PASSWORD="$(field "$CREDS" openstack_admin_password)"
fi

HARBOR_URL="$(field "$URLS" harbor)"

echo "==> イメージを構築 (linux/amd64)"
# 手元が Apple Silicon でも VM は amd64 なので明示する
docker build --platform linux/amd64 -t "lcn-infra-api:$TAG" "$API_REPO"

ssh_vm() {
  gcloud compute ssh "$VM" --tunnel-through-iap --zone="$ZONE" --project="$PROJECT" \
    --command="$1"
}

case "$HARBOR_URL" in
  https://*)
    HARBOR_HOST="$(printf '%s' "$HARBOR_URL" | sed -E 's#https://([^/]+)/?.*#\1#')"
    IMAGE="$HARBOR_HOST/library/lcn-infra-api:$TAG"
    echo "==> Harbor へ push: $IMAGE"
    echo "    （初回は docker login $HARBOR_HOST が要ります。"
    echo "      パスワードは terraform -chdir=staging/gcp output -json credentials）"
    docker tag "lcn-infra-api:$TAG" "$IMAGE"
    docker push "$IMAGE"
    ;;
  *)
    IMAGE="lcn-infra-api:$TAG"
    echo "==> Harbor が公開されていないので docker save で直接運びます（数分かかります）"
    docker save "lcn-infra-api:$TAG" | gzip | \
      gcloud compute ssh "$VM" --tunnel-through-iap --zone="$ZONE" --project="$PROJECT" \
        --command="gunzip | sudo docker load"
    ;;
esac

echo "==> VM 上の設定を更新して起動"
ssh_vm "
set -e
sudo sed -i 's|^LCN_INFRA_API_IMAGE=.*|LCN_INFRA_API_IMAGE=$IMAGE|' /opt/lc-staging/api/.compose.env
sudo sed -i 's|^OS_USERNAME=.*|OS_USERNAME=$OS_SERVICE_USERNAME|' /opt/lc-staging/api/.env
sudo sed -i 's|^OS_PASSWORD=.*|OS_PASSWORD=$OS_SERVICE_PASSWORD|' /opt/lc-staging/api/.env

# migrate は api/worker より先に完了させる（goose + river）
sudo /opt/lc-staging/api/dc up -d postgres
sudo /opt/lc-staging/api/dc run --rm migrate
sudo /opt/lc-staging/api/dc up -d api worker reconciler
sudo /opt/lc-staging/api/dc ps
"

echo ""
echo "配備しました: $IMAGE"
echo "  疎通確認（VM 上、認証なしで通る health）:"
echo "    gcloud compute ssh $VM --tunnel-through-iap --zone=$ZONE --command='curl -s localhost:8081/health/ready'"
echo "  外から:"
echo "    curl -H \"Authorization: Bearer <token>\" $(field "$URLS" infra_api)me"
