#!/usr/bin/env bash
# ローカル開発環境の各コンポーネントの現在状態を確認する(読み取り専用、副作用なし)。
# `documents/terraform/15-local-development.md` の構成に対応。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

ok()   { echo "  [OK]      $1"; }
miss() { echo "  [未セットアップ] $1"; }
warn() { echo "  [確認要]  $1"; }

echo "=== Authentik ==="
if [ -f local/authentik/.env ]; then ok ".env 生成済み"; else miss ".env 未生成 (local/authentik/.env.example からコピー)"; fi
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q authentik-server; then
  ok "コンテナ起動中 (http://localhost:9000)"
else
  miss "コンテナ未起動 (bash local/start.sh)"
fi

echo ""
echo "=== Vault (dev) ==="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx vault-dev; then
  ok "起動中 (http://localhost:8200, token: root)"
else
  miss "未起動 (bash local/start.sh)"
fi

echo ""
echo "=== kind ==="
if ! command -v kind >/dev/null 2>&1; then
  miss "kind 未インストール（documents/terraform/15-local-development.md の「3. kind」参照）"
elif kind get clusters 2>/dev/null | grep -qx lc-local; then
  ok "クラスター 'lc-local' 存在"
else
  miss "クラスター未作成 (bash local/start.sh)"
fi

echo ""
echo "=== act (GitHub Actions ローカル実行) ==="
if command -v act >/dev/null 2>&1; then ok "act インストール済み"; else miss "act 未インストール"; fi
if [ -f local/.secrets ]; then ok "local/.secrets 設定済み"; else miss "local/.secrets 未設定 (local/.secrets.example からコピー)"; fi
if [ -f local/.act.env ]; then ok "local/.act.env 設定済み"; else miss "local/.act.env 未設定 (local/.act.env.example からコピー)"; fi

echo ""
echo "=== GCP DevStack + Harbor VM ==="
if ! command -v terraform >/dev/null 2>&1; then
  miss "terraform 未インストール（documents/terraform/15-local-development.md の「1. OpenStack + Harbor（GCP VM）」参照）"
fi
if [ -f local/gcp-devstack/terraform.tfvars ]; then
  ok "terraform.tfvars 設定済み"
else
  miss "terraform.tfvars 未設定 (local/gcp-devstack/terraform.tfvars.example からコピー)"
fi

TF_STATE="local/gcp-devstack/terraform.tfstate"
if [ -f "$TF_STATE" ] && [ -s "$TF_STATE" ]; then
  ok "terraform state あり（VM 作成済みの可能性）"
  if command -v gcloud >/dev/null 2>&1 && [ -f local/gcp-devstack/windows-autostop/config.env ]; then
    # shellcheck disable=SC1091
    source local/gcp-devstack/windows-autostop/config.env
    if [ -n "${PROJECT_ID:-}" ] && [ -n "${ZONE:-}" ] && [ -n "${INSTANCE_NAME:-}" ]; then
      STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --project="$PROJECT_ID" --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
      if [ "$STATUS" = "RUNNING" ]; then
        ok "VM 状態: RUNNING"
      else
        warn "VM 状態: $STATUS (start-vm.sh で起動できます)"
      fi
    fi
  fi
else
  miss "terraform apply 未実行（VM 未作成。課金が発生するため必ずユーザーの明示確認を取ってから apply すること）"
fi

if [ -f local/gcp-devstack/windows-autostop/config.env ]; then
  ok "windows-autostop/config.env 設定済み"
else
  miss "windows-autostop/config.env 未設定"
fi

echo ""
echo "=== Terraform local-override ==="
if [ -f terraform/local-override.tf ]; then
  ok "terraform/local-override.tf 有効（ローカル向けプロバイダー設定が適用中）"
else
  miss "terraform/local-override.tf 未配置 (local/local-override.tf.example からコピー)"
fi

if [ -f local/clouds.yaml ]; then
  ok "local/clouds.yaml 設定済み"
else
  miss "local/clouds.yaml 未設定 (local/clouds.yaml.example からコピー)"
fi
