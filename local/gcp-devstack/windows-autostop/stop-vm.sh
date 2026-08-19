#!/usr/bin/env bash
# GCP の DevStack + Harbor VM を停止する（WSL / Linux から手動で使う版）。
# ロジックは stop-vm.ps1 と同一。自動監視(タスクスケジューラ)には使わない
# — それは常に Windows ネイティブの check-idle-and-stop.ps1 が担当する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config.env が見つかりません: $CONFIG_FILE" >&2
  echo "config.env.example をコピーして terraform output の値を入力してください" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${PROJECT_ID:?config.env に PROJECT_ID を設定してください}"
: "${ZONE:?config.env に ZONE を設定してください}"
: "${INSTANCE_NAME:?config.env に INSTANCE_NAME を設定してください}"

status=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" --format="value(status)" 2>/dev/null || true)

if [ "$status" = "RUNNING" ]; then
  echo "[gcp-devstack] stopping $INSTANCE_NAME ..."
  gcloud compute instances stop "$INSTANCE_NAME" --project="$PROJECT_ID" --zone="$ZONE" --quiet
else
  echo "[gcp-devstack] $INSTANCE_NAME is already '$status', nothing to do"
fi
