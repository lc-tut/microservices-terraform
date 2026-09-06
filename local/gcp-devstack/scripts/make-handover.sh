#!/usr/bin/env bash
# 共有相手に渡す接続手順書を local/handover/ に生成する。
# 認証情報を含むため出力先は gitignore 済み。端末には値を出さない。
#
#   bash local/gcp-devstack/scripts/make-handover.sh
set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$(cd "$TF_DIR/../.." && pwd)/local/handover"
mkdir -p "$OUT_DIR"

cd "$TF_DIR"
CREDS_JSON="$(terraform output -json shared_vm_credentials)"
if [ "$CREDS_JSON" = "null" ]; then
  echo "shared_vm_owner が未設定です。terraform.tfvars を確認してください" >&2
  exit 1
fi
PROJECT_ID="$(terraform output -raw project_id)"
OWNER="$(terraform output -json shared_vm_credentials >/dev/null && grep -oP '(?<=^shared_vm_owner\s=\s")[^"]+' terraform.tfvars)"

OUT_FILE="$OUT_DIR/devstack-$(date +%Y%m%d).md"

REPO_ROOT="$(cd "$TF_DIR/../.." && pwd)"

CREDS_JSON="$CREDS_JSON" PROJECT_ID="$PROJECT_ID" OWNER="$OWNER" REPO_ROOT="$REPO_ROOT" \
python3 - "$OUT_FILE" <<'PY'
import json, os, sys

c = json.loads(os.environ["CREDS_JSON"])
project = os.environ["PROJECT_ID"]
owner = os.environ["OWNER"]
out = sys.argv[1]

doc = f"""# LC-Cloud 開発用 OpenStack 環境（{owner} 用）

DevStack（OpenStack 一式）と Harbor が入った GCP の VM です。
本番の Polaris ではなく、壊しても問題ない検証用の環境です。

**このファイルにはパスワードが含まれます。** チャットや Git に貼らず、
手元だけで扱ってください。

---

## 環境の情報

| 項目 | 値 |
| --- | --- |
| GCP プロジェクト | `{project}` |
| VM 名 | `{c['instance']}` |
| ゾーン | `{c['zone']}` |
| 外部 IP | `{c['external_ip']}` |

| ログイン先 | ユーザー | パスワード |
| --- | --- | --- |
| OpenStack（Horizon / API） | `admin` | `{c['openstack_admin_password']}` |
| Harbor | `admin` | `{c['harbor_admin_password']}` |

---

## 1. 準備（最初の一回だけ）

gcloud CLI を入れて、自分の Google アカウントでログインします。

```bash
gcloud auth login
gcloud config set project {project}
```

VM へのアクセス権（`roles/iap.tunnelResourceAccessor`）は `{owner}` に
付与済みです。別のアカウントを使う場合は共有元に連絡してください。

---

## 2. VM を起動する

料金がかかるので、使うときだけ起動して、終わったら止めてください。

```bash
gcloud compute instances start {c['instance']} --zone={c['zone']}
```

止めるとき:

```bash
gcloud compute instances stop {c['instance']} --zone={c['zone']}
```

---

## 3. VM に入る

ファイアウォールは IAP 経由のみ許可しているため、`--tunnel-through-iap` が必要です。

```bash
gcloud compute ssh {c['instance']} --zone={c['zone']} --tunnel-through-iap
```

VM の中で OpenStack を操作する場合:

```bash
cd /opt/stack/devstack
source openrc admin admin
openstack server list
```

> `source openrc` は対話シェルでのみ動きます。スクリプトから使うときは
> `OS_AUTH_URL` などを明示的に export してください（下記「よくある詰まり」参照）。

---

## 4. 手元の PC から OpenStack / Harbor を使う

リポジトリの `local/gcp-devstack/windows-autostop/config.env` を作ります。

```bash
cd local/gcp-devstack
cp windows-autostop/config.env.example windows-autostop/config.env
```

`config.env` に次を書きます。

```bash
PROJECT_ID={project}
ZONE={c['zone']}
INSTANCE_NAME={c['instance']}
```

トンネルを張ります（使っている間は開いたままにする）。

```bash
./start-tunnels.sh &
```

| 用途 | URL |
| --- | --- |
| Horizon（OpenStack の画面） | http://localhost:18080/dashboard/ |
| OpenStack API | http://localhost:18080/identity/ |
| Harbor | http://localhost:18081/ |

`openstack` コマンドや Terraform を手元から使う場合は、`start-tunnels.sh` が
一緒に立てる SOCKS5 プロキシを通します（DevStack のカタログが VM 内部の
プライベート IP を返すため、これが無いとほとんどの操作が失敗します）。

```bash
export ALL_PROXY=socks5h://localhost:1080
export NO_PROXY=localhost,127.0.0.1
```

---

## 5. 入っているもの

Keystone / Nova / Neutron / Glance / Placement / Horizon / Cinder / Swift に加えて、
CloudKitty（Ceilometer + Gnocchi）と Trove（Barbican 含む）が動いています。

VM は入れ子の仮想化（KVM）が有効なので、Trove の DB インスタンスも実際に起動します。

```bash
openstack datastore list                  # mysql が出る
openstack image list                      # trove-guest-ubuntu-noble が出る

# DB インスタンスを作ってみる（ACTIVE / HEALTHY になるまで数分）
NET=$(openstack network show private -f value -c id)
openstack database instance create test-db \\
  --flavor m1.small --size 5 --datastore mysql --datastore-version 8.4 \\
  --nic net-id=$NET
```

> flavor のディスクサイズはゲストイメージ（約 1.4GB）より大きい必要があります。
> `m1.tiny`（1GB）では失敗するので `m1.small`（20GB）以上を使ってください。

---

## 6. よくある詰まり

**`source openrc` したのに認証エラーになる**

スクリプトや `ssh --command` から実行すると `OS_AUTH_URL` が空のまま、
エラーも出さずに進みます。明示的に指定してください。

```bash
export OS_AUTH_URL="http://$(hostname -I | awk '{{print $1}}')/identity"
export OS_USERNAME=admin
export OS_PASSWORD='{c['openstack_admin_password']}'
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
```

**手元から `openstack` コマンドが繋がらない**

SOCKS5 プロキシの設定を忘れていないか確認してください（上記 4 参照）。

**VM が勝手に止まる**

この VM ではアイドル自動停止を無効にしてあります。止まる場合は
`gcloud compute instances describe` で状態を確認してください。

**`stack.sh` をやり直したくなったら**

再実行してはいけません。DB だけ作り直されて起動済みサービスは
そのまま使われるため、元の失敗と無関係なエラーが増えます。

```bash
cd /opt/stack/devstack
sudo rm -f /opt/stack/horizon/openstack_dashboard/enabled/_32*.py
sudo rm -rf /opt/stack/async
./unstack.sh && ./clean.sh && ./stack.sh
```

---

## 7. 困ったら

リポジトリの `documents/terraform/15-local-development.md` に、
この環境の詳しい説明と既知の障害の一覧があります。
"""

# --- Authentik / IdP 作業用の認証情報 ---
# 相手の VM とは無関係な、組織で共有しているサービスの認証情報。
# 意図せず混ざらないよう、渡すキーをここで明示的に列挙する。
SHARE_KEYS = [
    "AUTHENTIK_TOKEN",
    "TF_VAR_smtp_host", "TF_VAR_smtp_port", "TF_VAR_smtp_username",
    "TF_VAR_smtp_password", "TF_VAR_smtp_use_tls", "TF_VAR_smtp_use_ssl",
    "TF_VAR_smtp_from_address",
    "TF_VAR_github_oauth_client_id", "TF_VAR_github_oauth_client_secret",
    "TF_VAR_discord_oauth_client_id", "TF_VAR_discord_oauth_client_secret",
]

secrets_path = os.path.join(os.environ["REPO_ROOT"], "local", ".secrets")
found = {}
if os.path.exists(secrets_path):
    with open(secrets_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k in SHARE_KEYS:
                found[k] = v.strip().strip('"').strip("'")

if found:
    lines = "\n".join(f"{k}={v}" for k, v in found.items() if v)
    doc += f"""
---

## 8. Authentik / IdP を触る場合

組織で共有しているサービスの認証情報です。**この VM とは無関係**で、
Authentik の Terraform（`terraform/platform/idp/`）を回すときに使います。

`local/.secrets` として保存してください（gitignore 済み）。

```bash
{lines}
```

自分の PC でローカル Authentik を立てる場合は、上記は不要です。
`local/start.sh` が各自の環境用に別途生成します。

> これらは共有アカウントの認証情報です。個別に無効化できないため、
> 不要になったら共有元に連絡してください。

### 意図的に渡していないもの

不足ではありません。理由があって外しています。

| 項目 | 理由 |
| --- | --- |
| State バックエンド（`AWS_ACCESS_KEY_ID` 等） | 各スタックに `backend_override.tf`（`backend "local" {{}}`）が置かれており、手元では自動的にローカル state になります。本番 state に触れずに開発できます。本番の認証情報を配ると CI の PR レビューを迂回して直接書き換えられるため渡しません |
| `TF_VAR_webhook_secret` | 空なら `webhook_enabled = false` となり Webhook 通知が作られないだけで、IdP の他の機能には影響しません。GitHub の `repository_dispatch` 連携まで触る場合のみ共有元に連絡してください |
| `LC_CLOUD_APP_CRED_*` | 共有元の VM 用です。この VM では自分で Application Credential を発行してください |
| GitHub / Bot のトークン | CI と Bot 用で、IdP 作業には不要です |

---

## 9. メンバー情報（PII）について

`terraform/platform/members/` の `*_secrets.yaml.enc` には
**メンバーの実メールアドレスと学籍番号**が入っています。復号には SOPS の
age 鍵が必要ですが、**この手順書には含めていません**。

復号が必要な場合は、自分の鍵を作って公開鍵を共有元に送ってください。

```bash
age-keygen -o ~/.config/sops/age/keys.txt
# 出力される age1... で始まる公開鍵だけを共有元に送る（秘密鍵は送らない）
```

共有元が `.sops.yaml` に追加して再暗号化すると復号できるようになります。
この方式なら秘密鍵が手元から出ず、アクセス権の変更が Git に残ります。
"""

with open(out, "w") as f:
    f.write(doc)
PY

chmod 600 "$OUT_FILE"
echo "生成しました: $OUT_FILE"
echo "（認証情報を含みます。安全な経路で渡してください）"
