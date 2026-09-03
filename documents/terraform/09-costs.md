# コスト・予算設計

## 概要

LC-Cloud は内部会計単位 **Credit** を用いてリソース使用量を計測し、
請求アカウントごとに月次予算を設定します。
Credit は実際の金銭とは対応しない内部ポイントです。

コスト計測には OpenStack の **CloudKitty**（Rating-as-a-Service）を使用します。
予算の強制は CloudKitty の `limit.rate` モジュールで行います。

---

## Credit 単位

**1 Credit = 1 vCPU-hour** をアンカー単位とします。

設計は [Jetstream2](https://docs.jetstream-cloud.org/general/access/)・
[NeCTAR](https://support.ehelp.edu.au/support/solutions/articles/6000257023)・
CMU Campus Cloud などの学術クラウドの SU（Service Unit）設計を参考にしています。

---

## リソース単価

| リソース | 単価 | 単位 |
|---|---|---|
| vCPU | 1.000 Credit | vCPU-hour あたり |
| RAM | 0.250 Credit | GB-hour あたり |
| ブロックストレージ（Cinder） | 0.002 Credit | GB-hour あたり |
| オブジェクトストレージ（Swift/S3） | 0.0005 Credit | GB-hour あたり |
| Floating IP | 0.500 Credit | IP-hour あたり（未アタッチでも課金） |

### 単価の根拠

| リソース | 根拠 |
|---|---|
| vCPU | 基準単位（Jetstream2 SU と同定義） |
| RAM | vCPU の 25%。CMU 実績比 ~28%、NeCTAR 設計比 25% の中間値 |
| ブロックストレージ | vCPU の 0.2%。データ保持を妨げない水準に設定 |
| オブジェクトストレージ | ブロックストレージの 1/4。S3 vs EBS の実コスト比に準拠 |
| Floating IP | vCPU の 50%。未アタッチでも課金しホーディングを抑制（AWS Elastic IP と同設計） |

---

## 月額コスト試算

クォータ上限をすべて 24 時間 × 30 日フル稼働させた場合の**最大値**です。
実際の使用量はこれより大幅に少なくなります。

| ティア | vCPU | RAM | ストレージ | Floating IP | 月額上限目安 |
|---|---|---|---|---|---|
| `lc-micro` | 2 | 4 GB | 50 GB | 1 | 約 2,600 Credits |
| `lc-small` | 4 | 8 GB | 100 GB | 2 | 約 5,200 Credits |
| `lc-standard-8` | 8 | 16 GB | 200 GB | 3 | 約 10,000 Credits |
| `lc-standard-16` | 16 | 32 GB | 400 GB | 5 | 約 19,700 Credits |
| `lc-standard-32` | 32 | 64 GB | 800 GB | 10 | 約 39,400 Credits |
| `lc-highmem-8` | 8 | 32 GB | 300 GB | 3 | 約 13,100 Credits |
| `lc-highcpu-16` | 16 | 16 GB | 200 GB | 5 | 約 16,500 Credits |

---

## デフォルト予算

請求アカウントの種別ごとにデフォルト予算を設定します。
カスタマイズが必要な場合のみ `catalog/billing-accounts/` にエントリを追加します（`08-billing.md` 参照）。

| 種別 | デフォルト予算 | 根拠 |
|---|---|---|
| 個人 | **5,000 Credits/月** | `lc-micro` フル稼働（~2,600）の約 2 倍。常時稼働 VM 1 台＋実験用途に十分な余裕 |
| チーム | **15,000 Credits/月** | `lc-small` フル稼働（~5,200）の約 3 倍。複数メンバーが並行して開発できる水準 |

---

## 予算アラート

| しきい値 | 動作 |
|---|---|
| 80% 到達 | Discord へ警告通知（新規リソース作成は可能） |
| 100% 到達 | 新規リソースの作成をブロック（既存リソースは停止しない） |

```text
月初リセット → 使用量の計測開始
  │
  ├─ 80% 到達 → Discord 警告
  │   「あと 20% で予算上限に達します」
  │
  └─ 100% 到達 → 新規リソース作成ブロック
      「予算上限に達しました。既存リソースは継続稼働します」
      「予算増額は catalog/billing-accounts/ にエントリを追加して PR してください」
```

---

## Terraform 実装

> **注意（実装との乖離・2026-09-03 調査 / 2026-09-03 Polaris 実機反映）**:
>
> - `openstack_rating_hashmap_service_v1`/`_field_v1`/`_mapping_v1` は
>   **どの Terraform Provider にも存在しません**。実際は
>   `terraform/modules/cloudkitty-service/`（`Mastercard/terraform-provider-restapi`
>   経由で CloudKitty の Hashmap API を直接叩く方式）を使います。
>   `terraform/platform/cloudkitty/` で実装し、ローカル DevStack と Polaris 実機の
>   両方で apply・`plan` clean・API GET での確認まで済んでいます。
> - `lc_cloud_budget`（下記「予算リソース」節）も存在しません。CloudKitty には
>   「複数のコスト源を横断して合算し、予算と比較する」機能自体が無く、
>   OpenStack 標準機能にも相当するものはありません。「Organization 単位での予算管理」は
>   まるごと自前実装が必要な未着手の課題です（今回のスコープ外）。
> - CloudKitty の `collector`・`scope_attribute` はいずれも **1 インスタンスにつき 1 つ**
>   しか設定できないため、OpenStack 用と Kubernetes 用は別インスタンスにします
>   （`documents/terraform/16-implementation-phases.md`「[P5]」参照）。
> - **OpenStack 側 collector（Polaris 実機）**: 当初想定の Gnocchi ではなく
>   **Prometheus collector**。Polaris(Kolla) は通知バス無効（`driver = noop`）で
>   Ceilometer の標準パイプラインが使えず、コントロールプレーンには触れない方針のため。
>   `openstack-exporter`(2.0.0-alpha) → Prometheus(recording rule で
>   `tenant_id`→`project_id` 正規化) → CloudKitty。基盤は
>   `terraform/platform/cloudkitty-infra/`（lc-dev の VM 1 台）。
> - restapi_object 経由で Hashmap API を操作する際の罠（provider `uri` に rating
>   エンドポイント URL をそのまま渡しモジュール側で `/v1/rating/module_config/hashmap/...`
>   を足す・JSON フィールド名は `map_type` ではなく `type`・値変更は `force_new` で
>   destroy→create・`ignore_server_additions = true` 必須）は
>   `terraform/modules/cloudkitty-service/main.tf` のコメントにまとめてあります。

### CloudKitty 単価設定（terraform/platform/cloudkitty/main.tf・Polaris 実機の実装）

Prometheus collector はプロジェクト単位の使用量そのもの（vCPU 数・RAM GB・
ボリューム GB・Floating IP 数）を qty として返すため、`field` で値をマッチングする
必要はなく、**service 直付けの flat mapping**（`cloudkitty-service` モジュールの
`service_rate` = `field_name` 省略時のモード）で単価を掛ける。`period = 3600` なので
qty はそのまま「その 1 時間の使用量」を表し、`単価 × qty` が Credit/時になる。
service 名は collector 設定（`metrics.yml` の `alt_name`）と一致させる。

```hcl
module "vcpu" {
  source       = "../../modules/cloudkitty-service"
  service_name = "vcpu"
  service_rate = { cost = "1.000000", type = "flat" } # 1.000 Credit / vCPU-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

module "memory" {
  source       = "../../modules/cloudkitty-service"
  service_name = "memory"
  service_rate = { cost = "0.250000", type = "flat" } # 0.250 Credit / GB-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

module "volume" {
  source       = "../../modules/cloudkitty-service"
  service_name = "volume"
  service_rate = { cost = "0.002000", type = "flat" } # 0.002 Credit / GB-hour（Cinder）
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}

module "floating_ip" {
  source       = "../../modules/cloudkitty-service"
  service_name = "floating_ip"
  service_rate = { cost = "0.500000", type = "flat" } # 0.500 Credit / IP-hour
  providers    = { restapi.cloudkitty = restapi.cloudkitty }
}
```

> オブジェクトストレージ（0.0005 Credit/GB-hour）は Polaris に Swift/S3(RGW) が
> 無いため未設定。RGW 導入時に exporter メトリクスと `module "object_storage"` を足す。
>
> フレーバー別など「メタデータの値ごとに単価を変えたい」場合は同じモジュールの
> **field モード**（`field_name = "flavor_id"` + `mappings = { ... }`）を使う。

### 予算リソース（catalog/billing-accounts/ で参照）

```hcl
# modules/lc-cloud-quota/budget.tf
resource "lc_cloud_budget" "this" {
  count           = var.budget_limit != null ? 1 : 0
  organization_id = var.organization_id
  limit_credits   = var.budget_limit

  alert_thresholds = [
    {
      percent  = 80
      action   = "notify"
      webhook  = var.discord_webhook_url
    },
    {
      percent  = 100
      action   = "block_create"
    }
  ]
}
```

---

## 予算の変更フロー

### 増額申請

```text
1. catalog/billing-accounts/<type>/<name>/ にエントリを作成（初回）
   または既存エントリの budget_limit を変更
2. PR → lc-cloud-infra または circle-admin が承認
3. apply → CloudKitty の予算が更新される
```

### デフォルト予算の全体変更

```text
1. 08-billing.md の変数デフォルト値を変更（設計文書）
2. modules/lc-cloud-quota/budget.tf の default を変更
3. platform/quotas/ を apply → 全アカウントのデフォルト予算に反映
```
