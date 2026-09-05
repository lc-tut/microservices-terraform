---
marp: true
theme: default
paginate: true
size: 16:9
header: "LC-Cloud 合宿"
---

<!--
note: 全体の位置づけ。Day1 14:30-18:00 の「オンボーディング」+「全体講習」で使う想定。
source: events-slide-src/schedule.md
-->

# LC-Cloudの合宿へようこそ

- 3日間、大阪でLC-Cloudのハンズオン開発合宿を行います
- Day2〜3はグループに分かれて実際に手を動かします
- 今日はその前提知識のインプットです

---

<!--
note: 便名・会場名などの確定値は schedule.md を正として当日までに verify する。
source: events-slide-src/schedule.md
todo: ホテル名・グループ会場（A/B）の割り当ては当日確定次第、発表者が口頭補足する
-->

# 会期の流れ

| Day | 主な内容 |
| --- | --- |
| Day1 | 移動 → オンボーディング → 全体講習 → レク |
| Day2 | 朝会 → グループ開発１〜４ → 中間発表 |
| Day3 | 朝会 → グループ開発５ → 成果発表 → 移動 |

- 詳細タイムテーブルは配布資料（`schedule.md`）を参照
- 昼食・夕食のタイミングも決まっているので確認しておいてください

---

<!--
note: 安全面の周知。ここは笑いを取る場面ではなく淡々と読み上げる。
source: events-slide-src/schedule.md
-->

# 注意事項

- 飲酒は禁止（未成年飲酒は当然厳禁）
- 開発が主目的です。時間中は開発に集中しましょう
- 預け荷物の禁制品には十分注意してください
- 体調管理は各自の裁量でお願いします
- **時間厳守**：25人を1人で管轄しているので、特に集合時間は絶対に守ってください

---

<!--
note: ここから技術パート（全体講習）に入る。前半は俯瞰、後半で今回のお題に絞り込む。
source: リポジトリ直下 README.md、documents/terraform/01-overview.md
-->

# 全体のスタック

LC-Cloud はこれらの要素で構成されています。

| レイヤー | 技術 |
| --- | --- |
| クラウド基盤 | OpenStack（Keystone / Nova / Neutron / Cinder / Octavia） |
| コンテナ基盤 | Kubernetes |
| IdP / 認証 | Authentik（OIDC） |
| コンテナレジストリ | Harbor |
| コスト管理 | CloudKitty |
| インフラ定義 | Terraform |
| CI/CD | GitHub Actions |
| シークレット管理 | SOPS（age暗号化） |

---

<!--
note: 予習・自習用のキーワード集。全部を今日説明しきらず「調べる入り口」を渡す位置づけ。
source: documents/terraform/01-overview.md, documents/terraform/12-openstack-resources.md
-->

# 調べる手掛かりのキーワード

- **OpenStack**: Keystone / Nova / Neutron / Cinder / Application Credential
- **認証**: OIDC / OAuth2 / JWT / SSO
- **IaC**: Terraform / State / Plan・Apply / Provider
- **API**: REST API / エンドポイント設計
- **コンテナ**: Docker / Kubernetes（Namespace・PVC・Secret）
- 気になったキーワードはグループ開発が始まる前に各自調べておいてください

---

<!--
note: ここでLC-Cloudの3層アクセスモデルとフェーズ進行を説明し、「今どこまでできているか」を共有する。
source: documents/terraform/02-repository-structure.md（3層モデル）, documents/terraform/16-implementation-phases.md
-->

# LC Cloudの全体像

**3層のアクセスモデル**で権限を分離しています。

| 層 | 誰が触るか | 内容 |
| --- | --- | --- |
| platform | 管理者のみ | IdP・GitHub Org・OpenStackネットワーク基盤 |
| catalog | 権限者（PR可） | チーム・プロジェクト・請求アカウント |
| workspaces | メンバー自由 | VM・DB・ストレージなど個々のリソース |

- 現在 Phase 0〜5（ローカル環境・CI・IdP・OpenStack基盤・catalog・モジュール）は実装・実機検証済み
- Phase 6（Middleware API）以降は未着手 ← **今回のお題**

---

<!--
note: 謎解き導入。「今回何を作るか」をいきなり言わずに、既存の設計を辿らせて気づかせる。
source: documents/terraform/13-operation-layers.md
-->

# みんなに作ってもらうものを調べてみよう

このリポジトリの設計にはこう書かれています。

> インフラの**作成・削除**は Terraform、
> VMの起動・停止・ログ取得など既存リソースへの**運用操作**は
> Middleware API が担当する。

- では、その「Middleware API」はもう存在する？
- 実装フェーズ表（`16-implementation-phases.md`）で確認してみましょう

---

<!--
note: 種明かし。Phase 6 が未着手であることを示し、次のスライドの成果物説明につなげる。
source: documents/terraform/16-implementation-phases.md Phase 6
-->

# 答え合わせ

```text
Phase 0  ローカル開発環境          ✅
Phase 1  GitHub / CI 基盤          ✅
Phase 2  Authentik（IdP）          ✅
Phase 3  OpenStack platform        ✅
Phase 4  catalog                   ✅
Phase 5  workspace モジュール      ✅（一部進行中）
Phase 6  Middleware API            ← ここ、まだない
```

- 今回みんなに作ってもらうのは、この **Middleware API 相当のUI/API** です

---

<!--
note: Terraform未経験者向けの基礎説明。宣言的・State・Plan/Applyの3点だけ押さえれば十分。
source: 一般知識（IaCツールの基礎）+ documents/terraform/01-overview.md ツール選定
-->

# Terraformってなに？

- **IaC（Infrastructure as Code）** ツールのひとつ
- インフラのあるべき姿を「宣言的」にコードで書く
  - 手順（どうやって作るか）ではなく、結果（何がある状態にしたいか）を書く
- `terraform plan` で差分確認 → `terraform apply` で反映
- 現在の状態は `State` に記録される
- Provider（AWS/GCP/OpenStack等）を通じて実際のAPIを叩く

---

<!--
note: 実際の活用実績を語るパート。実機検証済みという事実を強調して信頼感を出す。
source: documents/terraform/16-implementation-phases.md Phase 1-5
-->

# 今回のプロジェクトではTerraformでこんなことやってます

- **Authentik（IdP）**: 入会フロー・パスワードリセット・約70リソースを管理
- **GitHub**: Organization・Teams・Branch Protection・CODEOWNERS
- **OpenStack platform**: ネットワーク・イメージ・クォータ（実機Polarisで検証済み）
- **catalog**: チーム・プロジェクト作成をPRベースで自動化
  （実機でチーム・プロジェクト作成 → 削除までE2E検証済み）
- **CloudKitty**: 従量課金の単価設定をTerraformで管理
- **modules/lc-vm 等**: ワークスペースから使える再利用可能モジュール

---

<!--
note: 本題。今回のワークで作ってもらう成果物のゴールを明確に伝える。
source: documents/terraform/13-operation-layers.md, documents/terraform/14-middleware-architecture.md
-->

# 今回作ってもらうもの

**IdP基盤の認証をもとにAPIが叩けて、VM操作ができるUI（OpenStack）**

- Authentik で **OIDC ログイン**する
- 発行された **JWT** を検証してユーザーを認証する
- 認証済みユーザーが、**OpenStack API（Nova等）** をApplication Credential経由で叩く
- VMの一覧表示・起動・停止などの**運用操作**ができるUIを作る

これは設計ドキュメントでいう「Middleware API」（Phase 6）に相当します。

---

<!--
note: クロージング。質問受付とグループ開発への橋渡し。
-->

# Let's build

- 質問はいつでもどうぞ
- 次はグループに分かれてレク、そして明日からグループ開発です
- キーワードを予習しておくと明日からのスタートダッシュが違います
