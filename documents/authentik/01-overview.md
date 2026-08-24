# Authentik 詳細設計ディレクトリ

## 位置づけ

`documents/terraform/03-member-management.md` と `04-idp.md` が
Authentik まわりの基本設計（ファイル構成・enrollment フロー・PII 管理方針）を扱っているのに対し、
このディレクトリはその中でも特に作り込みが浅かった**メンバーのライフサイクル**
（卒業・OB/OG・年次の継続確認）を詳細設計するための場所です。

基本構成やファイルレイアウトは `03-member-management.md` に従います。
このディレクトリのドキュメントは、その上に乗る「卒業・継続まわりの運用」だけを掘り下げます。

---

## ドキュメント一覧

| ドキュメント | 内容 |
| --- | --- |
| [02-membership-lifecycle.md](02-membership-lifecycle.md) | active / ob-og / alumni の3層モデル（連絡の可否で線引き）、年次継続フロー（Authentik ネイティブ）、卒業フロー、アクセス権限マトリクス、Terraform への影響 |
| [04-discord-integration.md](04-discord-integration.md) | Discord Bot 連携（Authentik OAuth 経路 / Bot メール認証経路の二本立て）とロール同期 |
| [forms/](forms/00-overview.md) | 入会・年次継続確認・本名/連絡先登録の各フォームを、Authentik Terraform Provider の実スキーマと照合しながら要件定義したディレクトリ |

---

## 経緯（なぜこのディレクトリができたか）

`03-member-management.md` には元々「卒業・退会時」「年度末確認フロー」という節があり、
以下のような設計が書かれていました。

- 卒業年度のフォルダに継続者がいるかどうかだけを見て、いれば「対応不要」とする
- 継続の意思確認は個々のメンバー単位では行わない
- 卒業後も部活動に関わり続ける OB/OG という区分がない（`active` / `alumni` の二値のみ）

これは実装（`terraform/platform/idp/`, `terraform/platform/members/`）にも一切反映されておらず、
`grep -r graduation terraform/platform/` はヒットしません。設計として未成熟な状態でした。

`02-membership-lifecycle.md` はこれを置き換える形で、次の2点を明確に設計します。

1. **卒業時の移行**: 卒業年度の学生をどう `ob-og` / `alumni` に振り分けるか
2. **毎年の継続願**: 卒業と無関係に、在籍中の全メンバーに対して「来年度も続けるか」を
   毎年確認する仕組み（幽霊部員化を防ぐため）

`03-member-management.md` の該当節はこのドキュメントへのポインタに置き換えます。
