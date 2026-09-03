#!/usr/bin/env bash
# Polaris の CloudKitty VM(lc-dev/cloudkitty) 上でこのディレクトリごと同期し実行する。
#   scp -r stack rocky@<FIP>:/opt/cloudkitty && ssh ... 'cd /opt/cloudkitty/stack && sudo ./deploy.sh'
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "ERROR: .env が無い。cp .env.example .env して編集する"; exit 1; }
set -a; . ./.env; set +a

# cloudkitty.conf をレンダリング（テンプレの __VAR__ を .env の値で置換）
sed -e "s|__CK_DB_PASSWORD__|${CK_DB_PASSWORD}|g" \
    -e "s|__OS_ADMIN_PASSWORD__|${OS_ADMIN_PASSWORD}|g" \
    cloudkitty/cloudkitty.conf.tpl > cloudkitty/cloudkitty.conf
chmod 0644 cloudkitty/cloudkitty.conf cloudkitty/metrics.yml cloudkitty/policy.yaml

docker compose pull -q
docker compose up -d

echo "--- コンテナ起動待ち ---"
sleep 20
docker compose ps

# hashmap レーティングモジュールを有効化（冪等）
echo "--- enable hashmap rating module ---"
TOKEN=$(curl -s -D- -o /dev/null -X POST http://192.168.1.210:5000/v3/auth/tokens \
  -H 'Content-Type: application/json' \
  -d "{\"auth\":{\"identity\":{\"methods\":[\"password\"],\"password\":{\"user\":{\"name\":\"admin\",\"domain\":{\"name\":\"Default\"},\"password\":\"${OS_ADMIN_PASSWORD}\"}}},\"scope\":{\"project\":{\"name\":\"admin\",\"domain\":{\"name\":\"Default\"}}}}}" \
  | awk -F': ' '/^x-subject-token/{print $2}' | tr -d '\r')
# PUT /v1/rating/modules/<id> は 302 を返すが実際に反映される（-L は付けない。
# リダイレクト先へ PUT body が引き継がれず 400 になるため）。
curl -s -o /dev/null -X PUT http://127.0.0.1:8889/v1/rating/modules/hashmap \
  -H "X-Auth-Token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"module_id":"hashmap","enabled":true}' -w 'hashmap enable PUT -> HTTP %{http_code} (302/200 ならOK)\n'
curl -s http://127.0.0.1:8889/v1/rating/modules/hashmap -H "X-Auth-Token: $TOKEN" \
  -w '\n(verify) HTTP %{http_code}\n'

echo "--- done. カタログ登録は本ディレクトリ上位の README を参照 ---"
