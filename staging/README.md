# staging 環境

`local/` が「各自の手元にひとつずつ建てる開発環境」なのに対し、
`staging/` は **全員が同じ1組を共有する検証環境**です。GCP 上に
OpenStack(DevStack) と Authentik・Harbor・Middleware API を建て、
`terraform/platform/` 配下のコードを本番と同じまま staging へ向けて動かします。

- 手元だけで完結する動作確認 → [`../documents/terraform/15-local-development.md`](../documents/terraform/15-local-development.md)
- 本番をゼロから建てる → [`../documents/terraform/17-production-runbook.md`](../documents/terraform/17-production-runbook.md)

---

## 構成

```text
                    インターネット
                          │
        ┌─────────────────┴──────────────────┐
        │ 443 (誰でも)              80 (許可 CIDR のみ)
        ▼                                    ▼
 ┌──────────────────────────┐   ┌───────────────────────────┐
 │ lc-staging-platform      │   │ lc-staging-devstack       │
 │ e2-standard-4 10.20.0.11 │   │ n2-highmem-4  10.20.0.10  │
 │                          │   │                           │
 │ Caddy (Let's Encrypt)    │   │ DevStack (stable/2026.1)  │
 │  ├ auth.<zone>     ──┐   │   │   Keystone Nova Neutron   │
 │  ├ infra.<zone>    ──┼─┐ │   │   Glance Placement Horizon│
 │  └ harbor.<zone>   ──┼─┼─┼─┐ │   Cinder Swift Heat       │
 │                      │ │ │ │ │   CloudKitty(Ceilometer   │
 │ Authentik      :9000 ◀┘ │ │ │ │     + Gnocchi)           │
 │ lcn-infra-api  :8081 ◀──┘ │ │ │   Trove + Barbican       │
 │   api / worker / recon    │ │ │                           │
 │   + Postgres              │ │ │   internal-net / int-router│
 │ Harbor         :8080 ◀────┘ │ │   + subnetpool            │
 │                             │ └───────────────────────────┘
 └──────────────────────────┘  │            ▲
              │                              │
              └──── VPC 内で直接（10.20.0.10）┘
```

SSH は公開設定に関わらず **IAP トンネル経由のみ**です。

### 認証は OIDC（forward-auth ではない）

`lcn-infra-api` は Authentik Outpost の forward-auth ではなく、**API 自身が
Bearer の JWT を検証する OIDC 経路**で動かします
（[ADR-0017](https://github.com/lc-tut/lcn-infra-api/blob/main/docs/adr/0017-oidc-authentication.md)）。

そのため次のものが要りません。

| 要らないもの | 理由 |
| --- | --- |
| Authentik Outpost の Deployment | API が自分で署名検証する |
| Kubernetes | NetworkPolicy による「Outpost 以外から届かせない」強制が不要になった |
| Ingress の `auth-url` / `auth-signin` アノテーション | 同上 |

`X-authentik-*` ヘッダを信じる方式では、Outpost を経由しない経路に1本でも
到達できると誰にでもなりすませます。OIDC ではヘッダではなく署名を見るので、
その入口を塞ぐ責務がデプロイ側から消えます。結果として Kubernetes ではなく
Docker Compose で足りるようになり、staging の構成が1段簡単になっています。

`issuer` は Authentik が**リクエストの Host から組み立てます**。
`https://auth.<zone>` 以外の名前でログインして得たトークンは `iss` が変わり、
API に 401 で弾かれます。

### なぜ VM を2台に分けているか

DevStack のクリーン構築は 40〜50 分かかります。1台に同居させると、
作り直すたびに Authentik と Middleware API まで巻き込んで落ちます。

---

## 1. 構築

```bash
gcloud auth login
gcloud auth application-default login

cd staging/gcp
cp terraform.tfvars.example terraform.tfvars
# project_id / devstack_admin_password / iap_tunnel_users / dns_zone / acme_email
# / devstack_allowed_source_ranges を入力する

terraform init
terraform apply
```

state は本番と同じ GCS バケット（`linuxclub-network-cloud-terraform-state`）の
`tfstate/staging/gcp` に置きます。

### DNS レコードを作る

```bash
terraform -chdir=staging/gcp output dns_records
```

出てきた名前と IP で A レコードを作ってください。**作るまで Let's Encrypt の
証明書は発行されず HTTPS は繋がりません**（Caddy は取れるまで再試行し続けるので、
後から作れば放っておいても繋がるようになります）。

### bootstrap の完了を待つ

DevStack 側は **40〜50 分**、platform 側は 10〜15 分かかります。

```bash
gcloud compute ssh lc-staging-devstack --tunnel-through-iap \
  --zone=asia-northeast1-a --command="tail -f /var/log/lc-staging-bootstrap.log"
```

### 認証情報の取り出し

```bash
terraform -chdir=staging/gcp output -json credentials | jq
```

---

## 2. `terraform/platform/` を staging に向ける

本番と staging で **同じコードを** 使い、state だけ **Terraform workspace** で
分けます。GCS backend は state を `<prefix>/<workspace>.tfstate` に置くので、
`backend.tf` を1行も変えずに分離できます。本番は default workspace のままで、
これまでと何も変わりません。

```bash
staging/terraform/tf.sh platform/idp plan
staging/terraform/tf.sh platform/idp apply
staging/terraform/tf.sh platform/members plan
staging/terraform/tf.sh platform/openstack/quotas plan
```

`tf.sh` がやること:

1. `staging/gcp` の output から接続先と認証情報を読み、`AUTHENTIK_URL` /
   `AUTHENTIK_TOKEN` / `OS_*` を staging 向けに設定する
   （`.envrc` が本番向けに設定している application credential は打ち消します）
1. `terraform workspace select -or-create staging`
1. `staging/terraform/<root>.tfvars` があれば `-var-file` で渡す

> **本番向けに実行するときは `tf.sh` を使わないこと。**
> 素の `terraform` を叩けば default workspace のままです。

### Authentik の設定はどこまで入るか

ブランド（ロゴ・favicon・flow 背景）・全 Flow（enrollment / recovery /
annual_renewal / authentication）・ポリシー・グループは、**そのまま staging にも
入ります**。変数に依存しないただの Authentik リソースだからです。

ブランド画像は `terraform/platform/idp/assets/` を
raw.githubusercontent.com 経由で参照しています（`brand.tf`）。参照先が `main` に
固定されているので、**画像を差し替えたときは main に push するまで staging にも
反映されません**（未 push だと 404 になります）。

一方、**本番の値を入れると壊れる・事故るものが3つ**あります。いずれも空文字が
既定で、空なら該当リソースを作りません。`staging/terraform/platform-idp.tfvars`
にも同じことを書いてあります。

| 変数 | 本番の値を入れると |
| --- | --- |
| `github_oauth_client_id` / `discord_oauth_client_id` | GitHub/Discord 側に登録されたコールバック URL が本番 Authentik を指しているため、staging から認証を始めても戻ってこられない。試すなら OAuth App を別に作る |
| `webhook_secret` | **staging の Authentik が本番リポジトリに `repository_dispatch` を撃つ。** enrollment 完了で `auto-gen-members.yaml` を書き換える Bot が動いてしまう |
| `lc_cloud_oidc_client_id` | `provider_lc_cloud.tf` のリダイレクト URI が本番ホスト名で直書きされていて変数化されていないため、staging の DevStack を指せない。staging で Keystone フェデレーションを試すには、まずそこを変数にする必要がある |

### メールは本番と同じサーバーを使う

staging の Authentik には本番と同じ SMTP を設定します（`smtp_*` 変数）。
招待メールや年次継続確認の文面を実際に確認するためです。

> **本物のメールが本物の宛先に届きます。**
> 台帳（`members_secrets.yaml`）に入っているのは実在のメールアドレスです。
> `staging/terraform/platform-members.tfvars` は
> `send_enrollment_email = false` を既定にしていますが、**これを外して
> apply すると全 active メンバーに本物の招待メールが飛びます。**
> `smtp_from_address` は本番と見分けのつく値にしておいてください。

---

## 3. Middleware API を配備する

```bash
staging/platform/deploy-api.sh --repo ../lcn-infra-api
```

イメージを手元で構築し、Harbor があれば push、無ければ `docker save` で
VM へ運び、migrate を流してから `api` / `worker` / `reconciler` を起動します。
CI がイメージを publish するようになったら、この手順は pull に置き換えられます。

OpenStack のサービスアカウントは **staging では admin をそのまま使います**。
本番は [ADR-0014](https://github.com/lc-tut/lcn-infra-api/blob/main/docs/adr/0014-openstack-authentication.md)
のとおり専用アカウントを作り、全 project に `member` を付けてください。

### Authentik 側の設定

`terraform/platform/idp/provider_middleware.tf` が OIDC Provider と
scope mapping を作ります。`middleware_oidc_client_id` を設定したときだけ
作られます（既定は空＝作らない）。

mapping が載せるもの:

| claim | 中身 | 出どころ |
| --- | --- | --- |
| `lcn_id` | 台帳の不変 ID | `platform/members` の user attribute |
| `groups` | `team-<t>-<role>` などの**グループ名** | Authentik のグループ |
| `grants` | アドオン権限 | 同 user attribute |

`groups` は名前をそのまま入れます。`lcn-infra-api` は右端のハイフンで切って
scope とロールを導出するため（`modules/lc-role-map`）、ID や表示名に
変えてはいけません。

> **未検証**: Authentik の access token に上記の claim が期待どおり載ることは、
> まだ実機で確認していません（infra-api 側も `docs/operations/oidc.md` で
> 「実 Authentik の scope mapping は別の配備検証」としています）。
> staging で最初に確かめるのはここです。

---

## 4. 停止・破棄

公開している場合、**アイドル自動停止は既定で無効**です。判定材料が SSH の
有無しかなく、ブラウザや API から使われている最中でも止めてしまうためです。
時刻で絞りたい場合は `daily_start_time` / `daily_stop_time` を設定してください
（アクセスの有無は見ないので、使っている最中でも止まります）。

```bash
gcloud compute instances stop lc-staging-devstack lc-staging-platform \
  --zone=asia-northeast1-a
terraform -chdir=staging/gcp destroy
```

**止めるだけではディスクと静的 IP の課金が残ります**（250GB の pd-balanced で
月 5,180 円、静的 IP は停止中 月 1,745 円/個）。しばらく使わないなら destroy してください。

---

## 費用（asia-northeast1・税別・Cloud Billing Catalog の実価格）

| | devstack | platform | 合計 |
| --- | ---: | ---: | ---: |
| 24/7 | ¥42,768 | ¥22,621 | **¥65,389/月** |
| 毎日 9-23 時 | ¥26,667 | ¥14,196 | **¥40,863/月** |
| 平日 8h/日 | ¥13,994 | ¥7,564 | **¥21,558/月** |
| 3日間だけ建てて destroy | ¥4,218 | ¥2,231 | **¥6,449** |

devstack = n2-highmem-4 (4vCPU/32GB) + 150GB、platform = e2-standard-4 + 50GB。
停止中もディスク（月 4,144 円）と静的 IP（月 1,745 円/個）はかかります。

DevStack のスペックを変える場合（24/7・ディスクと IP 込み）:

| | 24/7 |
| --- | ---: |
| n2-standard-4 (4vCPU/16GB) — local と同一 | ¥32,680 |
| **n2-highmem-4 (4vCPU/32GB) — 既定** | ¥42,768 |
| n2-standard-8 (8vCPU/32GB) | ¥61,670 |

先に詰まるのは CPU ではなく RAM（Nova のゲスト VM に加えて Trove・
CloudKitty・Gnocchi が常駐する）ため、vCPU は local と同じ 4 のまま
メモリだけ倍にしています。

---

## OpenStack のサービス構成

**本番に寄せられるものは寄せ、重いもの・未検証のものは既定で切って**います。
実機 Polaris の Service Catalog（2026-09-04 時点）は
`cloudkitty / heat / placement / keystone / glance / neutron / cinder / nova`
だけで、Designate・Octavia・Manila・Swift・Trove は入っていません。

| 変数 | 既定 | 理由 |
| --- | --- | --- |
| `enable_telemetry` | **on** | 本番にある。CloudKitty のルールをこのリポジトリが管理している |
| `enable_heat` | **on** | 本番にある |
| （Swift） | **on** | Glance のバックエンド。`local/` で動作実績がある |
| `enable_trove` | **on** | `local/` で動作実績がある。`modules/lc-db` の検証に要る |
| `enable_designate` | off | staging では DNS を扱わない。本番にも無い |
| `enable_octavia` | off | amphora イメージ構築だけで 20〜30 分。LB 1つごとにゲスト VM が増える |
| `enable_manila` | off | 本番に無く、ドライバ選定から詰める必要がある |

切っている3つは `true` にできますが、**どれも実機で未検証**です。
`stack.sh` が落ちたら、まずここを疑ってください。
Octavia を有効にするなら `devstack_boot_disk_size_gb` を 200 に上げてください。

## ネットワークと Security Group

**本番と同じ形にしてあるもの**:

- **Security Group は `modules/lc-vm` が VM ごとに1つ作ります**
  （`<name>-sg`。SSH と ICMP を `remote_group_id` = 同じ SG のメンバーからだけ
  許可し、加えて `security_group_rules` で渡した分）。`internal-net` は
  全プロジェクト共有の L2 一枚なので、サブネット CIDR で絞ると他プロジェクトの
  VM まで通ってしまう——テナント境界を担っているのはこの SG です。
  staging 固有の差はありません。
- **VM を建てても Floating IP は払い出されません。** `modules/lc-vm` は
  Floating IP のリソースを一切持たず、VM は載せたネットワーク上の固定 IP だけを
  持ちます。外向きの通信は `int-router` 経由の SNAT です。
  （`catalog/projects/_template` が発行する CI 用 Application Credential の
  access rules には `/v2.0/floatingips` が含まれていますが、これは
  「API で取れる」だけで、Terraform が自動で取ることはありません。）
- 外向き通信は経路を問わず **`int-router` 1本**に集約します。プロジェクト個別の
  NAT・独自 LB は禁止で、これは本番と同じ設計判断です
  （`documents/terraform/12-openstack-resources.md`）。

**staging 固有のもの**:

外部ネットワークだけは DevStack が作る `public` をそのまま使います（本番は
`ext-net`）。`internal-net` / `int-subnet` / `int-router` / subnetpool は
`terraform/platform/openstack/network/` が**本番と同じコードで作ります**。

```bash
staging/terraform/tf.sh platform/openstack/network plan
```

ただし DevStack は `public` に `public-subnet` を既に作っているため、
`ext-subnet` の新規作成は CIDR の重複で失敗します。`access_as_external` の
RBAC ポリシーも同じく既存のものがあります。**どちらも import して管理下に
置いてください**（本番で RBAC ポリシーを import するのと同じ形です）。
手順は `staging/terraform/platform-openstack-network.tfvars` のコメントにあります。

import 後の `plan` が空になるまで、その tfvars の値を実機に合わせて直します。

## 4. 停止・破棄

公開している場合、**アイドル自動停止は既定で無効**です。判定材料が SSH の
有無しかなく、ブラウザや API から使われている最中でも止めてしまうためです。
時刻で絞りたい場合は `daily_start_time` / `daily_stop_time` を設定してください
（アクセスの有無は見ないので、使っている最中でも止まります）。

```bash
gcloud compute instances stop lc-staging-devstack lc-staging-platform \
  --zone=asia-northeast1-a
terraform -chdir=staging/gcp destroy
```

**止めるだけではディスクと静的 IP の課金が残ります**（250GB の pd-balanced で
月 5,180 円、静的 IP は停止中 月 1,745 円/個）。しばらく使わないなら destroy してください。

---

## 費用（asia-northeast1・税別・Cloud Billing Catalog の実価格）

| | devstack | platform | 合計 |
| --- | ---: | ---: | ---: |
| 24/7 | ¥42,768 | ¥22,621 | **¥65,389/月** |
| 毎日 9-23 時 | ¥26,667 | ¥14,196 | **¥40,863/月** |
| 平日 8h/日 | ¥13,994 | ¥7,564 | **¥21,558/月** |
| 3日間だけ建てて destroy | ¥4,218 | ¥2,231 | **¥6,449** |

devstack = n2-highmem-4 (4vCPU/32GB) + 150GB、platform = e2-standard-4 + 50GB。
停止中もディスク（月 4,144 円）と静的 IP（月 1,745 円/個）はかかります。

DevStack のスペックを変える場合（24/7・ディスクと IP 込み）:

| | 24/7 |
| --- | ---: |
| n2-standard-4 (4vCPU/16GB) — local と同一 | ¥32,680 |
| **n2-highmem-4 (4vCPU/32GB) — 既定** | ¥42,768 |
| n2-standard-8 (8vCPU/32GB) | ¥61,670 |

先に詰まるのは CPU ではなく RAM（Nova のゲスト VM に加えて Trove・
CloudKitty・Gnocchi が常駐する）ため、vCPU は local と同じ 4 のまま
メモリだけ倍にしています。

---

## OpenStack のサービス構成

**本番に寄せられるものは寄せ、重いもの・未検証のものは既定で切って**います。
実機 Polaris の Service Catalog（2026-09-04 時点）は
`cloudkitty / heat / placement / keystone / glance / neutron / cinder / nova`
だけで、Designate・Octavia・Manila・Swift・Trove は入っていません。

| 変数 | 既定 | 理由 |
| --- | --- | --- |
| `enable_telemetry` | **on** | 本番にある。CloudKitty のルールをこのリポジトリが管理している |
| `enable_heat` | **on** | 本番にある |
| （Swift） | **on** | Glance のバックエンド。`local/` で動作実績がある |
| `enable_trove` | **on** | `local/` で動作実績がある。`modules/lc-db` の検証に要る |
| `enable_designate` | off | staging では DNS を扱わない。本番にも無い |
| `enable_octavia` | off | amphora イメージ構築だけで 20〜30 分。LB 1つごとにゲスト VM が増える |
| `enable_manila` | off | 本番に無く、ドライバ選定から詰める必要がある |

切っている3つは `true` にできますが、**どれも実機で未検証**です。
`stack.sh` が落ちたら、まずここを疑ってください。
Octavia を有効にするなら `devstack_boot_disk_size_gb` を 200 に上げてください。

## ネットワークと Security Group

**本番と同じ形にしてあるもの**:

- **Security Group は `modules/lc-vm` が VM ごとに1つ作ります**
  （`<name>-sg`。SSH と ICMP を `remote_group_id` = 同じ SG のメンバーからだけ
  許可し、加えて `security_group_rules` で渡した分）。`internal-net` は
  全プロジェクト共有の L2 一枚なので、サブネット CIDR で絞ると他プロジェクトの
  VM まで通ってしまう——テナント境界を担っているのはこの SG です。
  staging 固有の差はありません。
- **VM を建てても Floating IP は払い出されません。** `modules/lc-vm` は
  Floating IP のリソースを一切持たず、VM は載せたネットワーク上の固定 IP だけを
  持ちます。外向きの通信は `int-router` 経由の SNAT です。
  （`catalog/projects/_template` が発行する CI 用 Application Credential の
  access rules には `/v2.0/floatingips` が含まれていますが、これは
  「API で取れる」だけで、Terraform が自動で取ることはありません。）
- 外向き通信は経路を問わず **`int-router` 1本**に集約します。プロジェクト個別の
  NAT・独自 LB は禁止で、これは本番と同じ設計判断です
  （`documents/terraform/12-openstack-resources.md`）。

**staging 固有のもの**:

本番では VPC Gateway ルーターと IP 帯域マスタープール（subnetpool）は
OpenStack 管理者が手で用意した既存インフラで、
`terraform/platform/openstack/network/` からはコードごと外されています
（コミット `644bd74`）。staging には用意してくれる管理者がいないので、
**仮のものを `staging/openstack/` で作ります**。

```bash
staging/terraform/tf.sh staging/openstack apply
terraform -chdir=staging/openstack output
```

出てくる `vpc_gateway_router_id` と `subnetpool_id` を
`catalog/projects/<p>/` の変数に渡してください。本番と同じ形を再現するのが
目的ではなく、`catalog/projects/` が動くのに必要な受け皿を置くだけなので、
帯域も名前も本番の値とは揃えていません（`10.100.0.0/16` を `/24` ずつ切り出す）。

外部ネットワークは DevStack が作る `public` をそのまま使います
（本番は `ext-net`）。`staging/terraform/platform-openstack-network.tfvars`
がその差を吸収します。

---

## 既知の落とし穴

DevStack 側は `local/gcp-devstack/` と同じ土台なので、そこで踏んだ問題は
そのまま起きます。対処は
[`../documents/terraform/15-local-development.md`](../documents/terraform/15-local-development.md)
の「`stack.sh` が途中で終わったあとの復旧」にまとまっています。特に:

- `stack.sh` は**失敗しても再実行してはいけない**。`unstack.sh` + `clean.sh`
  からやり直す
- 再構築の前に `/opt/stack/horizon/openstack_dashboard/enabled/_32*.py` と
  `/opt/stack/async` を消す

staging 固有:

- **Designate・Octavia・Manila は既定で無効です。** 実機 Polaris に存在せず、
  このリポジトリにも前例がありません。有効にして `stack.sh` が落ちたら、
  まずその3つを `false` に戻して切り分けてください。
- `platform/openstack/network/` を staging に apply すると、`ext-subnet` と
  `access_as_external` の RBAC ポリシーを新規作成しようとします。DevStack は
  どちらも既に持っているため失敗します。`terraform import` で取り込んでください
  （手順は `staging/terraform/platform-openstack-network.tfvars`。
  本番側の事情は `terraform/platform/openstack/network/README.md`）。
- Authentik を `https://auth.<zone>` 以外の名前で開いてログインすると、
  発行されるトークンの `iss` が変わり API に 401 で弾かれます。
