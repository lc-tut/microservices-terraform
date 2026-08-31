# フォーム要件一覧

`02-membership-lifecycle.md` で設計したメンバーライフサイクルの中で、
Authentik がホストする入力フォーム（Flow + Prompt Stage）を1つずつ切り出し、
フィールド仕様と Terraform 実装イメージを定義します。

---

## この下のドキュメントの検証方針

各フォームの実装可否は、**goauthentik/authentik Terraform Provider の実スキーマ**
（`mcp__terraform` の `get_provider_details` で取得した公式ドキュメント）と照合してから書いています。
特に以下は、書き始める前に必ず確認しています。

- そのフィールド・条件分岐が Provider のリソーススキーマ上に本当に存在するか
- Enterprise 限定機能（`authentik.enterprise.*` 名前空間）を要求していないか

これまでの検証で判明した、設計上よく間違えやすいポイント:

| 誤解しがちなこと | 実際 |
| --- | --- |
| Prompt Field 単位で表示条件（ポリシー）を付けられる | ❌ `authentik_stage_prompt_field` に条件分岐フィールドは存在しない |
| 条件分岐は `authentik_stage_prompt`（ステージ全体）を分けて実現する | ✅ `authentik_flow_stage_binding` ごとに `authentik_policy_binding` を紐づけて出し分ける |
| フィールド単位のバリデーション（必須/任意）しかできない | 一部△ `authentik_stage_prompt.validation_policies` で**ステージ全体**に対する
  カスタムバリデーション（例: 「A・Bどちらか1つは必須」）は書ける。個々の `required` は静的な真偽値のみ |
| ログインは username 固定 | ❌ `authentik_stage_identification.user_fields` に `"email"` を含めれば email ログインも可能（`recovery.tf` に前例あり） |
| Discord OAuth 連携は特別な実装が要る | ❌ `authentik_source_oauth.provider_type = "discord"` が公式にサポートされている（GitHubと同格） |
| Flow の途中でソース連携（`authentik_stage_source`）を挟める | ❌ Enterprise 限定と確認済み（公式ドキュメント `add-secure-apps/flows-stages/stages/source/` に Enterprise バッジあり）。`enrollment.tf` では代わりに静的な案内 Stage（`recommend_connect`）で代替している |
| `module "user"` という汎用モジュールがある | ❌ 存在しない。実装は `terraform/platform/members/authentik_users.tf` の `resource "authentik_user" "members"` に直接書かれている |

---

## ドキュメント一覧

| ドキュメント | フォーム | 状態 |
| --- | --- | --- |
| [01-enrollment.md](01-enrollment.md) | 入会フォーム | 実装済み・実機検証済み（GitHub/Discord連携の推奨案内Stage含む） |
| [02-annual-renewal.md](02-annual-renewal.md) | 年次継続確認フォーム（Q1 全員 / Q2 卒業年度: OB/OG・連絡不要・留年届） | Flow自体は実装済み・実機検証済み。ただしログイン時に自動で割り込ませる配線は未実装（`02-membership-lifecycle.md`「Terraformへの影響」参照） |
| [03-contact-info.md](03-contact-info.md) | 本名・個人連絡先登録フォーム | 実装済み・実機検証済み（`annual_renewal.tf` のStage 3として） |

Discord Bot の `/verify` はAuthentik上のフォームではない（Discord側で完結する）ため、
このディレクトリの対象外です。詳細は [../04-discord-integration.md](../04-discord-integration.md)。
