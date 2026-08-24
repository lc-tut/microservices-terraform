# 入会フォーム（既存・実装済み）

**状態: 実装済み**（`terraform/platform/idp/enrollment.tf`）。設計は
[`04-idp.md`](../../terraform/04-idp.md) の「入会フロー（enrollment flow）」に既にあります。
このドキュメントは `forms/` 配下のフォーム一覧を完結させるための短いポインタです。

## フィールド

| フィールド | 型 | 必須 | 備考 |
| --- | --- | --- | --- |
| `username` | text | ✅ | LC-Cloud Keystone ID と紐づく。以降変更不可。ポリシーで形式検証 |
| `name`（表示名） | text | ✅ | 本名ではなく自己申告のニックネーム的な表示名 |
| `password` / `password_repeat` | password | ✅ | |

招待コード検証（`authentik_stage_invitation`）→ 上記入力（`authentik_stage_prompt`）
→ ユーザー作成（`authentik_stage_user_write`, `user_creation_mode = "always_create"`）
→ ログイン、の4ステージ構成です。実装済みのため Terraform Provider 機能面の再検証は不要です。

`forms/03-contact-info.md` の「本名」フィールドは、ここで設定する「表示名」（`name`）とは
別物として扱います（本名は法的な氏名、表示名は自己申告のニックネームでも構わない）。

---

## 追加提案: Discord/GitHub連携を推奨する Stage（未実装・設計）

enrollment 完了直後（ログイン Stage の後）に、GitHub・Discord のアカウント連携を
**任意だが推奨**として案内する Stage を追加します。

### 実現方法の制約（要確認）

理想は「今すぐこの場で連携ボタンを押せる」ことですが、Authentik の
`authentik_stage_source`（Flow の途中でソース連携を行わせる Stage）は、
`authentik_policy_event_matcher` の `app` 許可値一覧を確認したところ
**`authentik.enterprise.stages.source` という Enterprise 名前空間にのみ存在し、
無印の `authentik.stages.source` は存在しません**。Terraform Provider のスキーマ上は
`authentik_stage_source` リソース自体が見えるため一見使えそうですが、
バックエンド機能自体が Enterprise 限定である可能性が高いです（本セッションでは
自己ホストの OSS 版を前提にしているため未確認・要検証）。

そのため、確実に OSS で動く代替として、**連携ページへの案内リンクを表示する
静的な Prompt Stage**（`type = "static"` または `"alert_info"`、Provider スキーマの
許可値に含まれることを確認済み）を Stage 5 として追加し、実際の連携操作は
enrollment 完了後に本人が Authentik の「Connected Sources」画面（ユーザー設定内）で
行ってもらう形にします。ボタンを押さず「後で」を選んでも先へ進める（スキップ可能）ようにします。

```hcl
# terraform/platform/idp/enrollment.tf への追記イメージ（未実装）
resource "authentik_stage_prompt_field" "recommend_connect" {
  name      = "enrollment-field-recommend-connect"
  field_key = "recommend_connect_info"
  label     = "GitHub・Discord連携のご案内"
  type      = "static"  # または alert_info。実機で表示内容にリンクを含められるか要確認
  sub_text  = <<-TEXT
    GitHub・Discord アカウントの連携は任意ですが、連携しておくと
    Organization への招待や OB/OG 向け Discord ロールの自動付与がスムーズになります。
    後からいつでも「Connected Sources」画面（ユーザー設定）から連携できます。
  TEXT
  order     = 100
}

resource "authentik_stage_prompt" "recommend_connect" {
  name   = "enrollment-recommend-connect"
  fields = [authentik_stage_prompt_field.recommend_connect.id]
}

resource "authentik_flow_stage_binding" "recommend_connect" {
  target = authentik_flow.enrollment.uuid
  stage  = authentik_stage_prompt.recommend_connect.id
  order  = 50  # login (order=40) の後
}
```

### 未決事項（要相談・要検証）

- `authentik_stage_source` が本当に Enterprise 限定かどうかの実機確認
  （OSS で使えるなら、この Stage は静的案内ではなく本物の連携ボタンに差し替えられる）
- `type = "static"` / `"alert_info"` の `sub_text` にリンク（Connected Sources 画面への URL）を
  埋め込めるか（Markdown/HTML が通るか）の実機確認。通らない場合は文字列での案内のみになる
- Connected Sources 画面の正確な URL パス（Authentik の SPA ルーティングに依存するため
  バージョンで変わる可能性があり、実装時にログインして確認する）
- GitHub 連携用の Stage も同じパターンで追加するか（`provider_github_source.tf` は既存だが、
  enrollment フロー内での案内 Stage はまだない）
