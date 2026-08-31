# 入会フォーム

**状態: 実装済み・実機検証済み**。ただし当初の設計（`authentik_invitation` を使った
招待制の `member-enrollment` Flow）は実際には使われておらず、2026-08-31 に
`terraform/platform/idp/enrollment.tf` ごと削除しました。理由と現在の実装は下記の通りです。

## なぜ enrollment.tf を削除したか

`enrollment.tf` は「招待コード検証 → username/表示名/パスワード入力 → ユーザー作成 → ログイン」
という4ステージ構成の独立 Flow（`member-enrollment`）を定義していましたが、

- この Flow を指す `authentik_invitation` リソースはリポジトリのどこにも存在しない
- `authentik_brand.default.flow_enrollment` にも設定されていない

ため、実際に新入会員がこの Flow を通る経路が存在しませんでした。

実際に新入会員がたどっている経路は次の通りです（`terraform/platform/members/authentik_users.tf`・
`terraform/platform/idp/recovery.tf`。詳細は
[`02-membership-lifecycle.md`](../02-membership-lifecycle.md) と
[`16-implementation-phases.md`](../../terraform/16-implementation-phases.md) の Phase 2 拡張節）。

1. 管理者が `members_secrets.yaml.enc` に email・student_id を追加して apply
2. Terraform が直接 `authentik_user` を作成（パスワード未設定＝`has_usable_password() == False`）
3. 「LinuxClubへようこそ！アカウント設定のお願い」メールが送信される
   （`member-recovery` Flow の welcome 分岐。`Accept-Language: ja` で日本語化済み）
4. 本人がリンクを開く → ようこそ案内 → username 決定 → パスワード設定 →
   GitHub/Discord連携のご案内 → 完了

## フィールド

| フィールド | 型 | 必須 | 備考 |
| --- | --- | --- | --- |
| `username` | text | ✅ | LC-Cloud Keystone ID と紐づく。以降変更不可。ポリシーで形式検証 |
| `password` / `password_repeat` | password | ✅ | |

（表示名の自己設定ステージは無し。`name` は Terraform 側が `lcn_id` で初期設定し、
本名は別途 `forms/03-contact-info.md` の `attributes.real_name` で扱う）

## GitHub・Discord連携のご案内 Stage

`recommend_connect`（`terraform/platform/idp/recovery.tf`）として実装済み・実機検証済み。
`type = "static"` の Prompt Stage（連携ボタンではなく案内文言のみ）で、パスワード設定完了直後、
初回のみ表示されます（`has_usable_password()` が False の間だけ表示するゲートを流用）。
`authentik_stage_source`（Flow内でその場連携させる機能）が Enterprise 限定と確認済みのため、
この静的案内 + 「後から Connected Sources 画面で連携してください」という案内に留めています。
