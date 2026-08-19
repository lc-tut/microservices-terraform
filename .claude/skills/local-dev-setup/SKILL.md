---
name: local-dev-setup
description: Set up, start, check the status of, or troubleshoot this repository's local development environment (Authentik, Vault dev, kind, act, and the GCP DevStack + Harbor VM). Use when the user asks to set up/start/reset the local dev environment, run `local/start.sh`, connect to the GCP DevStack + Harbor VM, open IAP tunnels, configure `terraform/local-override.tf` / `local/clouds.yaml` for local Terraform testing, or asks "ローカル環境を整えて" / "ローカルで動作確認したい" type requests.
---

# ローカル開発環境セットアップ

このスキルは `documents/terraform/15-local-development.md` に定義された
ローカル開発環境（Authentik / Vault dev / kind / act / GCP DevStack+Harbor VM）
を、現在の状態を壊さずにセットアップ・起動する手順を提供する。

**このスキルを使う前に必ず `documents/terraform/15-local-development.md` を読むこと。**
このファイルは手順の要約であり、コマンドの詳細・トラブルシューティングは
そちらが正。内容が食い違う場合は `15-local-development.md` を優先する。

## 全体方針

1. まず現状を確認する（何が既にセットアップ済みか）。
2. **無料・ローカル完結**のコンポーネント（Authentik / Vault / kind / act）は
   既存のスクリプトで自動セットアップしてよい。
3. **課金が発生する** GCP DevStack+Harbor VM の `terraform apply` は、
   状態を説明した上で必ずユーザーの明示的な GO をもらってから実行する。
   無断で apply しない。
4. シークレット・パスワードを**でっち上げない**。`openssl rand` 等で
   生成するか、ユーザーに入力してもらう。
5. 既存の `.env` / `clouds.yaml` / `terraform.tfvars` / `config.env` は
   **上書きしない**（既にあれば尊重してそのまま使う）。

## 手順

### 1. 現状確認

```bash
bash .claude/skills/local-dev-setup/scripts/status.sh
```

各コンポーネントの `[OK]` / `[未セットアップ]` / `[確認要]` が出力される。
これを見て、以降どのステップが必要か判断する。

### 2. Authentik / Vault / kind（無料・ローカル完結）

未セットアップなら、そのまま実行してよい（ユーザー確認不要、破壊的操作なし）。

```bash
bash local/start.sh
```

初回は `local/authentik/.env` が自動生成される（`SECRET` はスクリプトが
`openssl rand` で生成する。手で決め打ちしない）。

### 3. act（GitHub Actions ローカル実行）

`act` 未インストールならインストール手順を案内する
（`15-local-development.md` の「5. GitHub Actions (act)」参照。
`sudo mv` を伴うためユーザーに実行してもらうか、事前に確認を取る）。

`local/.secrets` / `local/.act.env` が無ければ `.example` からコピーする
（コピー自体は安全。中身の値（`AUTHENTIK_TOKEN` 等）はユーザーに入力を促す。
Claude が値を推測して埋めない）。

```bash
cp local/.secrets.example local/.secrets
cp local/.act.env.example local/.act.env
```

### 4. GCP DevStack + Harbor VM

`local/gcp-devstack/` の Terraform で構築する（詳細は
`15-local-development.md` の「1. OpenStack + Harbor（GCP VM）」）。

#### 4-1. VM が未作成の場合

`terraform apply` は実際に GCP 課金が発生する操作なので、
**必ず以下を実行前にユーザーに提示し、明示的な承認を得ること**:

- 対象プロジェクト ID
- マシンタイプ（デフォルト `e2-standard-4`）とおおよその時間単価
- `terraform plan` の出力

承認が取れたら:

```bash
cd local/gcp-devstack
[ -f terraform.tfvars ] || cp terraform.tfvars.example terraform.tfvars
# project_id / devstack_admin_password / harbor_admin_password が
# 未入力なら、ユーザーに直接入力してもらうか
# `openssl rand -base64 24` で生成した値を提案する
# iap_tunnel_users も必ず設定する（下記 4-3 参照。空のままだと
# IAP トンネルが使えず 4-3 で詰まる）

terraform init
terraform plan
# ここでユーザー承認 → terraform apply
```

`gcloud auth login` / `gcloud auth application-default login` が
未認証なら先に案内する（ブラウザ操作が必要）。

#### 4-2. VM は作成済みだが停止中の場合

これは課金を増やす操作だが破壊的ではないため、ユーザーが
「使いたい」と言っていれば確認は簡潔でよい（起動する旨を一言伝えれば十分）。

```bash
./local/gcp-devstack/windows-autostop/start-vm.sh
```

（`config.env` が無ければ `config.env.example` をコピーし、
`terraform output` の値で埋める）

#### 4-3. IAP トンネルを開く

VM が RUNNING なら、OpenStack API/Horizon・Harbor へアクセスするために
トンネルを張る（バックグラウンド実行、破壊的操作なし）。

トンネルには `roles/iap.tunnelResourceAccessor` ロールが必要。
`terraform.tfvars` の `iap_tunnel_users` に自分のメールアドレスを
`"user:you@example.com"` の形式で入れて `terraform apply` すれば
IAM ロールとして付与される（`main.tf` の `google_project_iam_member`
リソース）。gcloud で単発に付与するのではなく、この変数経由で
Terraform 管理するのが本リポジトリの方針。

```bash
./local/gcp-devstack/start-tunnels.sh &
```

`start-tunnels.sh` は IAP トンネルに加え SOCKS5 プロキシ
（`localhost:1080`）も立てる。DevStack のサービスカタログが VM 内部
プライベート IP（`HOST_IP`）を返すため、`openstack token issue` 以外の
ほぼ全ての `openstack`/`terraform` 操作にはこのプロキシが必須
（`ALL_PROXY=socks5h://localhost:1080` / `NO_PROXY=localhost,127.0.0.1`
を設定して使う。詳細は `15-local-development.md` 参照）。

#### 4-4. clouds.yaml / local-override.tf

```bash
[ -f local/clouds.yaml ] || cp local/clouds.yaml.example local/clouds.yaml
[ -f terraform/local-override.tf ] || cp local/local-override.tf.example terraform/local-override.tf
```

`local/clouds.yaml` の `application_credential_id` /
`application_credential_secret` は、初回は Keystone admin パスワード認証で
Application Credential を発行してから入力する必要がある
（`15-local-development.md` の「Application Credential の発行」参照）。
これはユーザーの操作が必要な箇所であり、Claude が代わりに秘密情報を
生成することはできない。

### 5. アイドル自動停止タスクの登録（Windows）

`schtasks` でタスクスケジューラにジョブを登録する操作は Windows
システムに永続的な変更を加えるため、**登録前に必ずユーザーに確認する**。
承認が得られたら手順は `15-local-development.md` の
「9. アイドル自動停止のセットアップ」を案内する
（管理者 PowerShell が必要なため、通常は Claude が代行実行せず
ユーザー自身に `register-scheduled-tasks.ps1` を実行してもらう）。

## トラブルシューティング

コンポーネントごとの詳細な手順・既知の制限事項は
`documents/terraform/15-local-development.md` の対応セクションを参照する:

| 症状 | 参照セクション |
| --- | --- |
| Authentik / Vault / kind が起動しない | 2, 3, 4 |
| act の実行が失敗する | 5. GitHub Actions (act) |
| OpenStack API に繋がらない | 1. OpenStack + Harbor（GCP VM）、IAP トンネル・IAM ロール |
| Harbor にログインできない | 1. OpenStack + Harbor（GCP VM）、Harbor へのログイン |
| GCP VM のコストが気になる | 9. アイドル自動停止のセットアップ |
