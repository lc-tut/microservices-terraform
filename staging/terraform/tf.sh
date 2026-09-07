#!/usr/bin/env bash
# terraform/platform/* の root を staging に向けて実行するラッパー。
#
#   staging/terraform/tf.sh platform/idp plan
#   staging/terraform/tf.sh platform/members apply
#   staging/terraform/tf.sh platform/openstack/quotas plan
#
# 本番と staging の state は **Terraform workspace** で分けている。
# GCS backend は state を <prefix>/<workspace>.tfstate に置くため、
# backend.tf を1行も変えずに分離できる。本番は default workspace のまま
# （<prefix>/default.tfstate）で、これまでと何も変わらない。
#
# **本番向けに実行するときは、このスクリプトを使わないこと。**
# 素の terraform を叩けば default workspace になる。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGING_TF="$REPO_ROOT/staging/terraform"
WORKSPACE=staging

if [ $# -lt 2 ]; then
  echo "使い方: $0 <root（terraform/ からの相対パス）> <terraform のサブコマンド...>" >&2
  echo "例:     $0 platform/idp plan" >&2
  exit 1
fi

ROOT="$1"; shift
# terraform/ 配下の root（本番と共用。workspace で state を分ける）と、
# staging/ 配下の staging 専用 root（本番に対応物が無い）の両方を受ける
if [ -d "$REPO_ROOT/terraform/$ROOT" ]; then
  ROOT_DIR="$REPO_ROOT/terraform/$ROOT"
  USE_WORKSPACE=1
elif [ -d "$REPO_ROOT/$ROOT" ]; then
  ROOT_DIR="$REPO_ROOT/$ROOT"
  # staging 専用の root は state がそもそも分かれているので workspace は使わない
  USE_WORKSPACE=0
else
  echo "root が見つかりません: terraform/$ROOT にも $ROOT にもありません" >&2
  exit 1
fi

# ---- staging の接続先を staging/gcp の output から組み立てる ----
GCP_DIR="$REPO_ROOT/staging/gcp"
tf_out() { terraform -chdir="$GCP_DIR" output -raw "$1" 2>/dev/null || true; }

CREDS="$(terraform -chdir="$GCP_DIR" output -json credentials 2>/dev/null || echo '{}')"
URLS="$(terraform -chdir="$GCP_DIR" output -json urls 2>/dev/null || echo '{}')"
jqr() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$2') or '')"; }

AUTHENTIK_TOKEN_VALUE="$(jqr "$CREDS" authentik_api_token)"
OS_ADMIN_PASSWORD="$(jqr "$CREDS" openstack_admin_password)"

if [ -z "$AUTHENTIK_TOKEN_VALUE" ]; then
  echo "staging/gcp の output が読めません。先に staging/gcp を apply してください" >&2
  exit 1
fi

# Authentik。公開していればその URL、していなければ IAP トンネル (start-tunnels.sh)
AUTHENTIK_HOST_URL="${LC_STAGING_AUTHENTIK_URL:-}"
if [ -z "$AUTHENTIK_HOST_URL" ]; then
  A="$(jqr "$URLS" authentik)"                       # 例 https://auth.<zone>/if/admin/
  AUTHENTIK_HOST_URL="$(printf '%s' "$A" | sed -E 's#(/if/admin/).*##; s#[[:space:]]*\(.*\)$##')"
fi

# OpenStack。公開していればその URL、していなければトンネル + SOCKS5
OS_URL="${LC_STAGING_OS_AUTH_URL:-}"
if [ -z "$OS_URL" ]; then
  O="$(jqr "$URLS" openstack)"                       # 例 http://openstack.<zone>/identity/
  OS_URL="$(printf '%s' "$O" | sed -E 's#[[:space:]]*\(.*\)$##')"
fi

export AUTHENTIK_URL="$AUTHENTIK_HOST_URL"
export AUTHENTIK_TOKEN="$AUTHENTIK_TOKEN_VALUE"
export TF_VAR_authentik_url="$AUTHENTIK_HOST_URL"
export TF_VAR_authentik_token="$AUTHENTIK_TOKEN_VALUE"

# .envrc が本番向けに設定している application credential を打ち消す。
# 残っていると staging の Keystone に本番の credential を送ってしまう
unset OS_APPLICATION_CREDENTIAL_ID OS_APPLICATION_CREDENTIAL_SECRET OS_AUTH_TYPE
export OS_AUTH_URL="$OS_URL"
export OS_USERNAME=admin
export OS_PASSWORD="$OS_ADMIN_PASSWORD"
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_REGION_NAME=RegionOne
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3
export TF_VAR_os_auth_url="$OS_URL"

# ---- workspace ----
cd "$ROOT_DIR"
terraform init -input=false >/dev/null

if [ "$USE_WORKSPACE" = 1 ]; then
  terraform workspace select -or-create "$WORKSPACE" >/dev/null

  CURRENT="$(terraform workspace show)"
  if [ "$CURRENT" != "$WORKSPACE" ]; then
    echo "workspace が $WORKSPACE になりませんでした（今: $CURRENT）。中断します" >&2
    exit 1
  fi
else
  WORKSPACE="(staging 専用 root)"
fi

# ---- staging 用の tfvars（あれば渡す） ----
# ファイル名は root のパスの / を - に置き換えたもの: platform/idp → platform-idp.tfvars
VARFILE="$STAGING_TF/$(printf '%s' "$ROOT" | tr '/' '-').tfvars"
EXTRA=()
case "${1:-}" in
  plan|apply|destroy|refresh|import|console|validate)
    [ -f "$VARFILE" ] && EXTRA+=("-var-file=$VARFILE")
    ;;
esac

echo "==> terraform ($ROOT) workspace=$WORKSPACE"
echo "    AUTHENTIK_URL=$AUTHENTIK_URL"
echo "    OS_AUTH_URL=$OS_AUTH_URL"
[ ${#EXTRA[@]} -gt 0 ] && echo "    ${EXTRA[*]}"
echo ""

exec terraform "$@" ${EXTRA[@]+"${EXTRA[@]}"}
