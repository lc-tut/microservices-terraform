#!/bin/bash
# platform VM の初回セットアップ。
#   - Docker + Authentik (Compose)
#   - k3s（traefik を外し ingress-nginx を入れる。NetworkPolicy は k3s 標準の
#     コントローラが強制する。lcn-infra-api はこれに依存している）
#   - Harbor（enable_harbor のとき）
#
# 2回目以降のブートはマーカーで丸ごとスキップし、サービスの起動確認だけ行う。
set -euo pipefail

MARKER=/opt/lc-staging/.bootstrapped
mkdir -p /opt/lc-staging
exec > >(tee -a /var/log/lc-staging-bootstrap.log) 2>&1

INTERNAL_IP="${internal_ip}"
DEVSTACK_IP="${devstack_internal_ip}"

if [ -f "$MARKER" ]; then
  echo "[lc-staging] already bootstrapped, ensuring services are up"
  systemctl start docker || true
  systemctl start k3s || true
  (cd /opt/lc-staging/authentik && docker compose up -d) || true
%{ if enable_harbor ~}
  (cd /opt/harbor-install/harbor && docker compose up -d) || true
%{ endif ~}
  exit 0
fi

echo "[lc-staging] first boot: installing Docker, Authentik, k3s"

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

# Harbor は TLS 無しの平文 HTTP で動かすため、push する側に insecure 指定が要る。
# staging は IAP の内側にしかいないのでこの構成にしている
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<DOCKERJSON
{
  "insecure-registries": ["$INTERNAL_IP:8080"]
}
DOCKERJSON
systemctl enable --now docker
systemctl restart docker

# --- Authentik ---
mkdir -p /opt/lc-staging/authentik
cat > /opt/lc-staging/authentik/docker-compose.yml <<'AUTHENTIK_COMPOSE'
${authentik_compose}
AUTHENTIK_COMPOSE

# イメージタグを staging 指定のものに合わせる（既定はリポジトリの複製元と同じ）
sed -i "s|ghcr.io/goauthentik/server:.*|ghcr.io/goauthentik/server:${authentik_version}|" \
  /opt/lc-staging/authentik/docker-compose.yml

# 秘密値は Terraform state から来る。.env は root のみ読める権限にする
cat > /opt/lc-staging/authentik/.env <<'AUTHENTIK_ENV'
PG_PASS=${authentik_pg_password}
AUTHENTIK_SECRET_KEY=${authentik_secret_key}
AUTHENTIK_BOOTSTRAP_PASSWORD=${authentik_bootstrap_password}
AUTHENTIK_BOOTSTRAP_TOKEN=${authentik_bootstrap_token}
AUTHENTIK_EMAIL__HOST=
AUTHENTIK_EMAIL__PORT=587
AUTHENTIK_EMAIL__USERNAME=
AUTHENTIK_EMAIL__PASSWORD=
AUTHENTIK_EMAIL__USE_TLS=true
AUTHENTIK_EMAIL__USE_SSL=false
AUTHENTIK_EMAIL__FROM=noreply@example.com
AUTHENTIK_ENV
chmod 600 /opt/lc-staging/authentik/.env

(cd /opt/lc-staging/authentik && docker compose up -d)

# --- k3s ---
# containerd が Harbor から平文 HTTP で pull できるようにする。
# k3s のインストール前に置く必要がある
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<REGISTRIES
mirrors:
  "$INTERNAL_IP:8080":
    endpoint:
      - "http://$INTERNAL_IP:8080"
REGISTRIES

# traefik を外すのは lcn-infra-api の deploy/ingress.yaml が
# nginx.ingress.kubernetes.io/auth-* アノテーションで forward-auth を組んでいるため。
# NetworkPolicy は無効化しない（--disable-network-policy を付けない）。
# k3s 標準のコントローラが強制する。これが無いと Outpost を経由しない経路から
# X-authentik-* ヘッダを詐称して誰にでもなりすませる
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

# k3s の helm-controller に ingress-nginx を入れさせる。
# manifests/ に置いたものは k3s が起動時に自動で適用する
mkdir -p /var/lib/rancher/k3s/server/manifests
cat > /var/lib/rancher/k3s/server/manifests/ingress-nginx.yaml <<'INGRESS'
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: ingress-nginx
  namespace: kube-system
spec:
  repo: https://kubernetes.github.io/ingress-nginx
  chart: ingress-nginx
  targetNamespace: ingress-nginx
  createNamespace: true
  valuesContent: |-
    controller:
      service:
        type: LoadBalancer
      ingressClassResource:
        default: true
      # forward-auth のレスポンスヘッダ（X-authentik-*）を素通しするために
      # スニペットは要らない。auth-url / auth-response-headers だけで足りる
      allowSnippetAnnotations: false
INGRESS

# k3s が上がるのを待つ（helm-controller が chart を引くまで数分かかる）
for i in $(seq 1 60); do
  if k3s kubectl get --raw /readyz >/dev/null 2>&1; then break; fi
  sleep 5
done

# root 以外からも kubectl を使えるようにしておく
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' > /etc/profile.d/k3s.sh
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl 2>/dev/null || true

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
# hostname は内部 IP。k3s の containerd も docker push もこの名前で引く。
# localhost:28081（IAP トンネル）で開くのはブラウザ閲覧用で、push には使えない
# （Harbor が自分の hostname でトークンとリダイレクトを発行するため）
sed -i "s|^hostname:.*|hostname: $INTERNAL_IP|" harbor.yml
sed -i "s/^  port: 80\$/  port: 8080/" harbor.yml
# https ブロックを丸ごとコメントアウト（TLS なしの平文 HTTP 運用）
sed -i "/^https:/,/private_key:/s/^/#/" harbor.yml
sed -i "s|^harbor_admin_password:.*|harbor_admin_password: ${harbor_admin_password}|" harbor.yml

./install.sh
%{ endif ~}

# --- 接続情報のメモを VM 上に残す ---
cat > /opt/lc-staging/README <<INFO
lc-staging platform VM

  Authentik : http://$INTERNAL_IP:9000/if/admin/   (compose: /opt/lc-staging/authentik)
  Harbor    : http://$INTERNAL_IP:8080/            (compose: /opt/harbor-install/harbor)
  k3s       : sudo k3s kubectl get nodes
  DevStack  : http://$DEVSTACK_IP/identity/        (別 VM)

手元からは IAP トンネル越しに開く: staging/start-tunnels.sh
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
