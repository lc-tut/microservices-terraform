#!/bin/bash
# GCE の metadata_startup_script として毎回ブート時に実行される。
# 初回のみ DevStack のフルインストールを行い、以降はマーカーファイルでスキップする
# （VM の start/stop を繰り返す運用のため）。
#
# local/gcp-devstack/scripts/bootstrap.sh.tpl から Harbor を除いたもの。
# staging では Harbor を platform VM 側に置いている（DevStack を作り直しても
# イメージレジストリが消えないようにするため）。
# それ以外の修正（KVM のグループ・Trove のゲスト疎通・br-ex の FORWARD 等）は
# 実機で踏んだ問題への対処なので、そのまま引き継いでいる。
set -euo pipefail

MARKER=/opt/lc-staging/.bootstrapped
mkdir -p /opt/lc-staging
exec > >(tee -a /var/log/lc-staging-bootstrap.log) 2>&1

if [ -f "$MARKER" ]; then
  echo "[lc-staging] already bootstrapped, ensuring docker is running"
  systemctl start docker || true
  exit 0
fi

echo "[lc-staging] first boot: installing Docker and DevStack"
echo "[lc-staging] this can take 20-40 minutes (mostly stack.sh)"

# --- Docker ---
export DEBIAN_FRONTEND=noninteractive

# stack.sh の初回実行が apt-daily 系タイマーと dpkg/debconf のロックを取り合い、
# 「Could not get lock」で落ちることがある（VM 作成直後に起きやすい）。
# 先に止めておく
systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service 2>/dev/null || true
systemctl mask apt-daily.timer apt-daily-upgrade.timer apt-daily.service \
  apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null || true

apt-get update -y
apt-get install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# --- KVM ---
# ネステッド仮想化が有効でも、kvm モジュールを明示的にロードしておかないと
# Nova が最初に使う時点で遅延ロードされ、そのとき /dev/kvm のグループが
# kvm ではなく render になることがある。libvirt-qemu は kvm グループにしか
# 属していないため、こうなるとインスタンス起動が
# 「Could not access KVM kernel module: Permission denied」で失敗する。
echo kvm_intel > /etc/modules-load.d/kvm.conf
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0660"' > /etc/udev/rules.d/99-kvm.rules
modprobe kvm_intel || true
udevadm control --reload-rules && udevadm trigger --name-match=kvm || true

# --- DevStack ---
# 公式手順に倣い、root ではなく専用の非特権ユーザー stack で stack.sh を実行する
if ! id -u stack >/dev/null 2>&1; then
  useradd -s /bin/bash -d /opt/stack -m stack
  echo "stack ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/stack
fi
# Ubuntu 24.04 は useradd -m のホーム権限既定を 750 に強化しており、
# Apache (www-data) が /opt/stack/data/venv を stat できずに
# Keystone 等の WSGI リクエストが全滅して stack.sh がハングする。
chmod o+rx /opt/stack

INTERNAL_IP="${internal_ip}"

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

disable_service tempest

# CloudKitty（課金・クォータ関連の Hashmap ルールを Terraform から管理するため）。
# stable/2026.1 の既定通り fetcher/collector=gnocchi・storage=influxdb。
# Gnocchi は OpenStack 本体からは独立したプロジェクトのため github.com/gnocchixyz を参照する
enable_plugin ceilometer https://opendev.org/openstack/ceilometer stable/2026.1
enable_plugin gnocchi https://github.com/gnocchixyz/gnocchi master
enable_plugin cloudkitty https://opendev.org/openstack/cloudkitty stable/2026.1
enable_service ck-api,ck-proc

# Trove（DBaaS）。modules/lc-db の検証用。Cinder と Barbican に依存するため
# これらは無効化しない
enable_plugin trove https://opendev.org/openstack/trove stable/2026.1
enable_service trove tr-api tr-tmgr tr-cond
enable_plugin barbican https://opendev.org/openstack/barbican stable/2026.1

# Swift。Glance のバックエンドとして使う
enable_service swift
SWIFT_HASH=66a3d6b56c1f479c8b4e70ab5c2000f5

# Swift の 1 オブジェクト上限。DevStack は loopback ディスクのサイズから 1GiB を
# 選ぶことがあるが、Trove のゲストイメージ（約 1.4GiB）がこれを超え、Glance への
# アップロードが 413 で失敗して stack.sh ごと止まる
SWIFT_MAX_FILE_SIZE=5368709122
LOCALCONF

  cd devstack
  ./stack.sh
"

# --- Trove のゲストが通信できるようにする ---
# DevStack 標準の構成のままだと Trove のゲスト VM は起動しない。以下 4 点が
# 揃って初めて guest-agent が RabbitMQ に到達し、MySQL イメージを取得できる。
su stack -c "
  cd /opt/stack/devstack && source openrc admin admin >/dev/null 2>&1

  # (1) ゲストは mgmt 網にしかいないが、guest-agent の接続先は br-ex 上の
  #     172.24.4.1 が既定になっており経路がない。ホストの mgmt 側 IP に向ける
  MGMT_IP=\$(ip -4 -o addr show trove-mgmt 2>/dev/null | awk '{print \$4}' | cut -d/ -f1)
  if [ -n \"\$MGMT_IP\" ]; then
    sudo sed -i \"s|@172\\.24\\.4\\.1:5672|@\$MGMT_IP:5672|\" /etc/trove/trove-guestagent.conf
  fi

  # (2) trove-mgmt のセキュリティグループは 22 と ICMP しか許可しておらず AMQP が落ちる
  SG=\$(openstack security group list --name trove-mgmt -f value -c ID 2>/dev/null | head -1)
  [ -n \"\$SG\" ] && openstack security group rule create --ingress --protocol tcp \
      --dst-port 5672 --remote-ip 192.168.254.0/24 \"\$SG\" >/dev/null 2>&1 || true

  # (3) ゲスト内の ens3(テナント網側)は networking.service の失敗で落ちるため、
  #     確実に上がっている mgmt 網側にルーティングを持たせる
  openstack subnet set --no-allocation-pool \
    --allocation-pool start=192.168.254.10,end=192.168.254.200 \
    --gateway 192.168.254.254 trove-mgmt-subnet >/dev/null 2>&1 || true
  openstack router add subnet router1 trove-mgmt-subnet >/dev/null 2>&1 || true

  # (4) 名前解決用。サブネットに DNS が無いとイメージの取得に失敗する
  openstack subnet set --dns-nameserver 8.8.8.8 private-subnet >/dev/null 2>&1 || true
  openstack subnet set --dns-nameserver 8.8.8.8 trove-mgmt-subnet >/dev/null 2>&1 || true

  sudo systemctl restart devstack@tr-api devstack@tr-tmgr devstack@tr-cond >/dev/null 2>&1 || true
"

# Docker が FORWARD の既定ポリシーを DROP にするため、テナント網から br-ex 経由で
# 外へ出る転送が落ちる。ホスト自身の通信は通るので気づきにくい
iptables -C FORWARD -i br-ex -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i br-ex -j ACCEPT
iptables -C FORWARD -o br-ex -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -o br-ex -j ACCEPT

# --- アイドルシャットダウン ---
IDLE_MINUTES="${idle_shutdown_minutes}"
if [ "$IDLE_MINUTES" -gt 0 ]; then
  cat > /usr/local/bin/idle-shutdown.sh <<IDLE_SCRIPT
#!/bin/bash
# SSH 接続（IAP トンネル含む）が $IDLE_MINUTES 分間なければシャットダウンする。
# staging へのアクセスは全て IAP トンネル越しなので、
# トンネルが1本も無い = 誰も使っていない、と判断できる。
IDLE_MINUTES=$IDLE_MINUTES
STAMP=/run/last-ssh-connection

# stack.sh / unstack.sh は 30 分以上かかるうえ nohup で切り離して実行するため、
# SSH を張っていなくても「作業中」である。実行中に停止すると DevStack が
# 中途半端な状態で壊れる
if pgrep -f '(^|/)(un)?stack\.sh' >/dev/null 2>&1; then
  touch "\$STAMP"; exit 0
fi

# 任意の長時間作業を手動で保護するための抑止ファイル。
# 使い方: sudo touch /run/no-idle-shutdown（解除は rm）
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
echo "[lc-staging] devstack bootstrap complete"
