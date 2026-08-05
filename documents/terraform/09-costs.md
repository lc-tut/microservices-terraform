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

### CloudKitty 単価設定（platform/quotas/cloudkitty.tf）

```hcl
# terraform/platform/quotas/cloudkitty.tf

resource "openstack_rating_hashmap_service_v1" "compute" {
  name = "compute"
}

resource "openstack_rating_hashmap_field_v1" "vcpu" {
  service_id = openstack_rating_hashmap_service_v1.compute.id
  name       = "vcpus"
}

resource "openstack_rating_hashmap_mapping_v1" "vcpu_rate" {
  field_id = openstack_rating_hashmap_field_v1.vcpu.id
  type     = "flat"
  cost     = "1.0"   # 1 Credit / vCPU-hour
}

resource "openstack_rating_hashmap_field_v1" "ram" {
  service_id = openstack_rating_hashmap_service_v1.compute.id
  name       = "memory_mb"
}

resource "openstack_rating_hashmap_mapping_v1" "ram_rate" {
  field_id = openstack_rating_hashmap_field_v1.ram.id
  type     = "flat"
  # 0.25 Credit/GB-hour = 0.000244 Credit/MB-hour
  cost     = "0.000244"
}

resource "openstack_rating_hashmap_service_v1" "volume" {
  name = "volume"
}

resource "openstack_rating_hashmap_mapping_v1" "volume_rate" {
  service_id = openstack_rating_hashmap_service_v1.volume.id
  type       = "flat"
  cost       = "0.002"   # 0.002 Credit / GB-hour
}

resource "openstack_rating_hashmap_service_v1" "network_floating" {
  name = "network.floating"
}

resource "openstack_rating_hashmap_mapping_v1" "floating_rate" {
  service_id = openstack_rating_hashmap_service_v1.network_floating.id
  type       = "flat"
  cost       = "0.5"   # 0.5 Credit / IP-hour（未アタッチでも課金）
}
```

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
