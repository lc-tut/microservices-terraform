#!/bin/bash
# platform VM の初回セットアップ。
#   - Docker + Authentik (Compose)
#   - Caddy（TLS 終端・Let's Encrypt 自動取得。dns_zone を設定したときだけ）
#   - Harbor（enable_harbor のとき）
#   - lcn-infra-api 用の control-plane DB（イメージは deploy-api.sh が後から入れる）
#
# 認証は OIDC（API 自身が JWT を検証する）。Authentik Outpost の forward-auth も
# Kubernetes も使わない。詳しくは staging/README.md。
#
# 2回目以降のブートはマーカーで丸ごとスキップし、サービスの起動確認だけ行う。
set -euo pipefail

MARKER=/opt/lc-staging/.bootstrapped
mkdir -p /opt/lc-staging
exec > >(tee -a /var/log/lc-staging-bootstrap.log) 2>&1

INTERNAL_IP="${internal_ip}"
DEVSTACK_IP="${devstack_internal_ip}"

compose_up_all() {
  (cd /opt/lc-staging/authentik && docker compose up -d) || true
%{ if publish ~}
  (cd /opt/lc-staging/caddy && docker compose up -d) || true
%{ endif ~}
%{ if enable_harbor ~}
  (cd /opt/harbor-install/harbor && docker compose up -d) || true
%{ endif ~}
  # イメージがまだ無ければ api 群は上がらない。postgres だけは必ず起こす
  (cd /opt/lc-staging/api && docker compose up -d postgres) || true
  (cd /opt/lc-staging/api && docker compose up -d) || true
}

if [ -f "$MARKER" ]; then
  echo "[lc-staging] already bootstrapped, ensuring services are up"
  systemctl start docker || true
  compose_up_all
  exit 0
fi

echo "[lc-staging] first boot: installing Docker, Authentik, Caddy"

export DEBIAN_FRONTEND=noninteractive
systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service 2>/dev/null || true
systemctl mask apt-daily.timer apt-daily-upgrade.timer apt-daily.service \
  apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null || true

apt-get update -y
apt-get install -y ca-certificates curl gnupg git jq

# --- Docker ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# --- 名前解決 ---
# この VM 自身が公開ホスト名を引いたときは、外へ出ずに内側へ落とす。
# GCE の VM は自分の外部 IP へ折り返せないため、公開 DNS のまま引くと届かない。
%{ if publish ~}
grep -q " ${auth_host}\$"   /etc/hosts || echo "127.0.0.1 ${auth_host}"   >> /etc/hosts
grep -q " ${infra_host}\$"  /etc/hosts || echo "127.0.0.1 ${infra_host}"  >> /etc/hosts
grep -q " ${harbor_host}\$" /etc/hosts || echo "127.0.0.1 ${harbor_host}" >> /etc/hosts
# OpenStack は別 VM。VPC 内の内部 IP へ向ける
grep -q " ${openstack_host}\$" /etc/hosts || echo "$DEVSTACK_IP ${openstack_host}" >> /etc/hosts
%{ endif ~}

# --- Authentik ---
mkdir -p /opt/lc-staging/authentik
cat > /opt/lc-staging/authentik/docker-compose.yml <<'AUTHENTIK_COMPOSE'
${authentik_compose}
AUTHENTIK_COMPOSE

sed -i "s|ghcr.io/goauthentik/server:.*|ghcr.io/goauthentik/server:${authentik_version}|" \
  /opt/lc-staging/authentik/docker-compose.yml

# 秘密値は Terraform state から来る。.env は root のみ読める権限にする
cat > /opt/lc-staging/authentik/.env <<'AUTHENTIK_ENV'
PG_PASS=${authentik_pg_password}
AUTHENTIK_SECRET_KEY=${authentik_secret_key}
AUTHENTIK_BOOTSTRAP_PASSWORD=${authentik_bootstrap_password}
AUTHENTIK_BOOTSTRAP_TOKEN=${authentik_bootstrap_token}
AUTHENTIK_EMAIL__HOST=${smtp_host}
AUTHENTIK_EMAIL__PORT=${smtp_port}
AUTHENTIK_EMAIL__USERNAME=${smtp_username}
AUTHENTIK_EMAIL__PASSWORD=${smtp_password}
AUTHENTIK_EMAIL__USE_TLS=${smtp_use_tls}
AUTHENTIK_EMAIL__USE_SSL=${smtp_use_ssl}
AUTHENTIK_EMAIL__FROM=${smtp_from_address}
AUTHENTIK_ENV
chmod 600 /opt/lc-staging/authentik/.env

(cd /opt/lc-staging/authentik && docker compose up -d)

%{ if publish ~}
# --- Caddy（TLS 終端） ---
# host ネットワークで動かす。Authentik(9000)・infra-api(8081)・Harbor(8080) は
# どれも 127.0.0.1 に bind しているものへ proxy するため、
# コンテナ間ネットワークを跨ぐ必要がない。
#
# 証明書は Let's Encrypt の HTTP-01 で自動取得する。**A レコードがこの VM の
# 外部 IP を指すまで発行されない。** Caddy は取れるまで再試行し続けるので、
# DNS を後から設定しても放っておけば繋がるようになる。
mkdir -p /opt/lc-staging/caddy

cat > /opt/lc-staging/caddy/Caddyfile <<'CADDYFILE'
{
	email ${acme_email}
}

# Authentik。OIDC の issuer はここから組み立てられる:
#   https://${auth_host}/application/o/<application-slug>/
# Authentik はリクエストの Host と X-Forwarded-Proto から自分の URL を作るため、
# Caddy を通した瞬間に https の issuer になる。Caddy は host ネットワークなので
# 送信元が 127.0.0.1 になり、Authentik の既定の信頼プロキシ範囲に入る。
${auth_host} {
	reverse_proxy 127.0.0.1:9000
}

# lcn-infra-api。Bearer の JWT を持つ要求をそのまま通す。
# forward-auth のアノテーションに相当するものは無い（OIDC 方式のため）。
${infra_host} {
	reverse_proxy 127.0.0.1:8081
}
%{ if enable_harbor ~}

${harbor_host} {
	# docker push でイメージ層を送るため、既定の本文サイズ上限を外す
	request_body {
		max_size 0
	}
	reverse_proxy 127.0.0.1:8080
}
%{ endif ~}
CADDYFILE

cat > /opt/lc-staging/caddy/docker-compose.yml <<'CADDY_COMPOSE'
services:
  caddy:
    image: caddy:2-alpine
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
CADDY_COMPOSE

(cd /opt/lc-staging/caddy && docker compose up -d)
%{ endif ~}

# --- lcn-infra-api（DB だけ先に用意する） ---
# イメージは staging/platform/deploy-api.sh が後から入れる。
mkdir -p /opt/lc-staging/api
cat > /opt/lc-staging/api/docker-compose.yml <<'API_COMPOSE'
${api_compose}
API_COMPOSE

# compose 自体が読む変数（イメージ名・DB パスワード・extra_hosts の中身）
cat > /opt/lc-staging/api/.compose.env <<'COMPOSE_ENV'
LCN_DB_PASSWORD=${infra_db_password}
LCN_AUTH_HOST=${auth_host}
LCN_OPENSTACK_HOST=${openstack_host}
LCN_DEVSTACK_INTERNAL_IP=${devstack_internal_ip}
LCN_INFRA_API_IMAGE=lcn-infra-api:not-deployed-yet
COMPOSE_ENV

# アプリが読む環境変数。
# **OS_USERNAME / OS_PASSWORD は空のまま。** DevStack 構築後に
# サービスアカウントを作ってから deploy-api.sh が埋める（ADR-0014）。
cat > /opt/lc-staging/api/.env <<'API_ENV'
LCN_ENV=staging
LCN_ADDR=:8080
LCN_LOG_LEVEL=debug

# --- 認証: OIDC（Bearer の JWT を API 自身が検証する） ---
LCN_AUTH_MODE=oidc
LCN_OIDC_ISSUER=https://${auth_host}/application/o/${oidc_client_id}/
LCN_OIDC_AUDIENCE=${oidc_client_id}
# uid claim には台帳の attributes.lcn_id が載る mapping が必須
# （terraform/platform/idp/provider_middleware.tf が作る）
LCN_OIDC_UID_CLAIM=lcn_id
LCN_OIDC_USERNAME_CLAIM=preferred_username
LCN_OIDC_GROUPS_CLAIM=groups
LCN_OIDC_TIMEOUT=10s

# --- control-plane DB ---
LCN_DATABASE_URL=postgres://lcn:${infra_db_password}@postgres:5432/lcn_infra?sslmode=disable
# 一覧カーソルの署名鍵。全レプリカで同じ値にすること
LCN_CURSOR_SECRET=${cursor_secret}

# --- OpenStack（ADR-0014: 単一サービスアカウント + project スコープトークン） ---
OS_AUTH_URL=http://${openstack_host}/identity/
OS_REGION_NAME=RegionOne
OS_INTERFACE=public
OS_USERNAME=
OS_PASSWORD=
OS_USER_DOMAIN_ID=default
OS_PROJECT_DOMAIN_ID=default

LCN_TERRAFORM_STOP_POLICY=warn
LCN_SHUTDOWN_TIMEOUT_SECONDS=20
API_ENV
chmod 600 /opt/lc-staging/api/.env /opt/lc-staging/api/.compose.env

# compose は同じディレクトリの .env を「変数の定義元」と「env_file」の両方に
# 使ってしまう。役割を分けるため、変数定義は .compose.env に置いて
# --env-file で明示的に渡す。誤用を防ぐためのラッパーを置いておく
cat > /opt/lc-staging/api/dc <<'DC'
#!/bin/bash
# 使い方: /opt/lc-staging/api/dc up -d
exec docker compose --env-file /opt/lc-staging/api/.compose.env \
  -f /opt/lc-staging/api/docker-compose.yml "$@"
DC
chmod +x /opt/lc-staging/api/dc

/opt/lc-staging/api/dc up -d postgres

%{ if enable_harbor ~}
# --- Harbor ---
# DevStack VM ではなく platform VM に置いている。DevStack はクリーン構築を
# 繰り返す前提なので、そこに置くとイメージが毎回消える
HARBOR_VERSION="${harbor_version}"
mkdir -p /opt/harbor-install
cd /opt/harbor-install
curl -fsSL -o harbor-online-installer.tgz \
  "https://github.com/goharbor/harbor/releases/download/$HARBOR_VERSION/harbor-online-installer-$HARBOR_VERSION.tgz"
tar xzf harbor-online-installer.tgz
cd harbor

cp harbor.yml.tmpl harbor.yml
sed -i "s|^hostname:.*|hostname: ${harbor_host}|" harbor.yml
sed -i "s/^  port: 80\$/  port: 8080/" harbor.yml
# Harbor 自身は TLS を張らない。前段の Caddy が終端する
sed -i "/^https:/,/private_key:/s/^/#/" harbor.yml
sed -i "s|^harbor_admin_password:.*|harbor_admin_password: ${harbor_admin_password}|" harbor.yml
%{ if publish ~}
# 前段で TLS 終端している場合、Harbor が発行するリダイレクトと docker の
# トークン要求先を外向きの URL に合わせる必要がある
sed -i "s|^# external_url:.*|external_url: https://${harbor_host}|" harbor.yml
grep -q '^external_url:' harbor.yml || echo "external_url: https://${harbor_host}" >> harbor.yml
%{ endif ~}

./install.sh
%{ endif ~}

# --- 接続情報のメモを VM 上に残す ---
cat > /opt/lc-staging/README <<INFO
lc-staging platform VM

%{ if publish ~}  Authentik : https://${auth_host}/if/admin/
  infra-api : https://${infra_host}/api/infra/v1/
  Harbor    : https://${harbor_host}/
%{ else ~}  Authentik : http://$INTERNAL_IP:9000/if/admin/   (IAP トンネル経由)
  Harbor    : http://$INTERNAL_IP:8080/
%{ endif ~}  OpenStack : http://${openstack_host}/identity/   (別 VM: $DEVSTACK_IP)

  Authentik : /opt/lc-staging/authentik  (docker compose)
  Caddy     : /opt/lc-staging/caddy
  infra-api : /opt/lc-staging/api        (./dc up -d  で操作する)
  Harbor    : /opt/harbor-install/harbor
INFO

# --- アイドルシャットダウン ---
IDLE_MINUTES="${idle_shutdown_minutes}"
if [ "$IDLE_MINUTES" -gt 0 ]; then
  cat > /usr/local/bin/idle-shutdown.sh <<IDLE_SCRIPT
#!/bin/bash
# SSH 接続（IAP トンネル含む）が $IDLE_MINUTES 分間なければシャットダウンする。
IDLE_MINUTES=$IDLE_MINUTES
STAMP=/run/last-ssh-connection

if [ -e /run/no-idle-shutdown ]; then
  touch "\$STAMP"; exit 0
fi

if ss -tn state established '( sport = :22 )' | grep -q ESTAB 2>/dev/null; then
  touch "\$STAMP"; exit 0
fi

[ -f "\$STAMP" ] || { touch "\$STAMP"; exit 0; }

LAST=\$(stat -c %Y "\$STAMP")
NOW=\$(date +%s)
IDLE=\$(( NOW - LAST ))

if [ "\$IDLE" -ge \$(( IDLE_MINUTES * 60 )) ]; then
  logger -t idle-shutdown "No SSH for \$${IDLE_MINUTES}m — shutting down"
  systemctl poweroff
fi
IDLE_SCRIPT
  chmod +x /usr/local/bin/idle-shutdown.sh

  cat > /etc/systemd/system/idle-shutdown.service <<'EOF'
[Unit]
Description=Idle shutdown - stop VM when SSH has been absent

[Service]
Type=oneshot
ExecStart=/usr/local/bin/idle-shutdown.sh
EOF

  cat > /etc/systemd/system/idle-shutdown.timer <<'EOF'
[Unit]
Description=Run idle-shutdown check every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now idle-shutdown.timer
fi

touch "$MARKER"
echo "[lc-staging] platform bootstrap complete"
