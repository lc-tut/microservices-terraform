#!/bin/bash
# GCE の metadata_startup_script として毎回ブート時に実行される。
# 初回のみ DevStack + Harbor のフルインストールを行い、以降はマーカーファイルで
# スキップして Docker デーモンの起動確認だけを行う（VM の start/stop を
# 繰り返す運用のため）。
set -euo pipefail

MARKER=/opt/gcp-devstack/.bootstrapped
mkdir -p /opt/gcp-devstack
exec > >(tee -a /var/log/gcp-devstack-bootstrap.log) 2>&1

if [ -f "$MARKER" ]; then
  echo "[gcp-devstack] already bootstrapped, ensuring docker is running"
  systemctl start docker || true
  exit 0
fi

echo "[gcp-devstack] first boot: installing Docker, DevStack, Harbor"
echo "[gcp-devstack] this can take 20-40 minutes (mostly stack.sh)"

# --- Docker ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck disable=SC1091
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# --- DevStack ---
# 公式手順（https://opendev.org/openstack/devstack）に倣い、root ではなく
# 専用の非特権ユーザー stack で stack.sh を実行する
if ! id -u stack >/dev/null 2>&1; then
  useradd -s /bin/bash -d /opt/stack -m stack
  echo "stack ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/stack
fi
# Ubuntu 24.04 は `useradd -m` のホームディレクトリ権限デフォルトを 750 に
# 強化しており、Apache (www-data) が /opt/stack/data/venv (mod_wsgi の
# PYTHONHOME) を stat できず Permission denied で Keystone 等の WSGI
# リクエストが全滅し stack.sh がハングする既知の問題があるため、
# 明示的に他ユーザーからの走査権限を付与する
chmod o+rx /opt/stack

INTERNAL_IP=$(hostname -I | awk '{print $1}')

sudo -u stack -H bash -c "
  set -euo pipefail
  cd /opt/stack
  if [ ! -d devstack ]; then
    git clone -b stable/2026.1 https://opendev.org/openstack/devstack
  fi

  cat > devstack/local.conf <<'LOCALCONF'
[[local|localrc]]
HOST_IP=$INTERNAL_IP
ADMIN_PASSWORD=${devstack_admin_password}
DATABASE_PASSWORD=${devstack_admin_password}
RABBIT_PASSWORD=${devstack_admin_password}
SERVICE_PASSWORD=${devstack_admin_password}
SERVICE_TOKEN=${devstack_admin_password}

# 15-local-development.md の構成（Keystone / Nova / Neutron / Glance /
# Placement / Horizon）に必要な範囲に絞り、Cinder / Tempest はフットプリント
# 削減のため無効化する。他のサービスは DevStack のデフォルトに従う
disable_service tempest
disable_service c-api
disable_service c-vol
disable_service c-sch
disable_service c-bak
LOCALCONF

  cd devstack
  ./stack.sh
"

# --- Harbor（最小構成: install.sh を追加フラグなしで実行） ---
HARBOR_VERSION="${harbor_version}"
mkdir -p /opt/harbor-install
cd /opt/harbor-install
curl -fsSL -o harbor-online-installer.tgz \
  "https://github.com/goharbor/harbor/releases/download/$HARBOR_VERSION/harbor-online-installer-$HARBOR_VERSION.tgz"
tar xzf harbor-online-installer.tgz
cd harbor

cp harbor.yml.tmpl harbor.yml
sed -i "s/^hostname:.*/hostname: ${external_ip}/" harbor.yml
sed -i "s/^  port: 80\$/  port: 8080/" harbor.yml
# https ブロックを丸ごとコメントアウト（TLS なしの平文 HTTP 運用にする。
# ローカル開発用の Authentik / Vault と同じ方針）
sed -i "/^https:/,/private_key:/s/^/#/" harbor.yml
sed -i "s/^harbor_admin_password:.*/harbor_admin_password: ${harbor_admin_password}/" harbor.yml

./install.sh

# --- アイドルシャットダウン（SSH 接続が途絶えたら自動停止） ---
# IAP トンネルは SSH ベースのため、接続が N 分なければ誰も作業していないと判断する
cat > /usr/local/bin/idle-shutdown.sh <<'IDLE_SCRIPT'
#!/bin/bash
# SSH 接続（IAP トンネル含む）が IDLE_MINUTES 分間なければシャットダウンする
IDLE_MINUTES=30
STAMP=/run/last-ssh-connection

if ss -tn state established '( sport = :22 )' | grep -q ESTAB 2>/dev/null; then
  touch "$STAMP"
  exit 0
fi

[ -f "$STAMP" ] || { touch "$STAMP"; exit 0; }

LAST=$(stat -c %Y "$STAMP")
NOW=$(date +%s)
IDLE=$(( NOW - LAST ))

if [ "$IDLE" -ge $(( IDLE_MINUTES * 60 )) ]; then
  logger -t idle-shutdown "No SSH for ${IDLE_MINUTES}m — shutting down"
  systemctl poweroff
fi
IDLE_SCRIPT
chmod +x /usr/local/bin/idle-shutdown.sh

cat > /etc/systemd/system/idle-shutdown.service <<'EOF'
[Unit]
Description=Idle shutdown — stop VM when SSH has been absent for 30 min

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

touch "$MARKER"
echo "[gcp-devstack] bootstrap complete"
