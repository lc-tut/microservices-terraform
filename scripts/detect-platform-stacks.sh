#!/usr/bin/env bash
# terraform/platform/ 配下で変更されたファイルから、実際に apply/plan すべき
# Terraform root module（= backend.tf を持つ最も近い祖先ディレクトリ）を
# 一意に列挙する。
#
# platform/ 配下は idp/ のようにフラット直下がそのまま root module のものと、
# openstack/quotas/ のようにカテゴリディレクトリの下にネストしたものが混在する。
# 固定階層数（$1/$2/$3 決め打ち）だと後者で壊れるため、backend.tf の有無で
# 実際の root を判定する。
#
# 標準入力: git diff --name-only の出力（1行1ファイルパス、全体でよい。
#           terraform/platform/ 以外の行は無視する）
# 標準出力: root module のパスを1行1件、重複無しソート済みで出力
set -euo pipefail

declare -A seen

while IFS= read -r f; do
  [[ "$f" == terraform/platform/* ]] || continue

  d="$(dirname "$f")"
  while [[ "$d" != "terraform/platform" && "$d" != "." && "$d" != "/" ]]; do
    if [[ -f "$d/backend.tf" ]]; then
      seen["$d"]=1
      break
    fi
    d="$(dirname "$d")"
  done
done

for k in "${!seen[@]}"; do
  echo "$k"
done | sort -u
