#!/bin/bash
# terraform/platform/members/{active,ob-og,alumni}/**/*.yaml.enc を同名の平文ファイルへ復号する。
# terraform plan/apply の前に実行する（復号後の平文ファイルは .gitignore 対象）。
set -euo pipefail

cd "$(dirname "$0")/.."

for enc in terraform/platform/members/{active,ob-og,alumni}/*/*.yaml.enc; do
  [ -e "$enc" ] || continue
  sops --decrypt "$enc" > "${enc%.enc}"
done
