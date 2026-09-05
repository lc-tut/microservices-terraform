# スライド構成一覧

対象セッション: Day1 14:30-18:00「オンボーディング（全体）」+「全体講習（全体）」
（`schedule.md` 参照。休憩は各セクションの区切りで適宜想定）

| # | スライドタイトル | 狙い | 主な情報源 |
| --- | --- | --- | --- |
| 1 | LC-Cloudの合宿へようこそ | つかみ。今日〜明後日で何をするかの一言サマリ | — |
| 2 | 会期の流れ | Day1〜3 のタイムテーブルを俯瞰させる | `schedule.md` |
| 3 | 注意事項 | 飲酒・預け荷物・時間厳守など安全面の周知 | `schedule.md` |
| 4 | 全体のスタック | LC-Cloud を構成する技術要素を一望させる | リポジトリ README、`01-overview.md` |
| 5 | 調べる手掛かりのキーワード | グループ開発前に各自で予習してほしい語彙を提示 | `01-overview.md`、`12-openstack-resources.md` |
| 6 | LC Cloudの全体像 | 3層アクセスモデルとフェーズ進行状況を説明 | `02-repository-structure.md`（3層）、`16-implementation-phases.md` |
| 7 | みんなに作ってもらうものを調べる | 答え合わせ形式で今回のお題（Middleware API）に気づかせる | `13-operation-layers.md`、`16-implementation-phases.md` Phase 6 |
| 8 | Terraformってなに？ | IaC・宣言的構成・State の基礎知識 | 一般知識 + `01-overview.md` ツール選定 |
| 9 | 今回のプロジェクトではTerraformでこんなことやってます | 本リポジトリでの実例（IdP・OpenStack・課金・カタログ） | `16-implementation-phases.md` Phase 1-5 |
| 10 | 今回作ってもらうもの：IdP認証 + VM操作UI | 成果物のゴールを明示 | `13-operation-layers.md`、`14-middleware-architecture.md` |
| 11 | Let's build | グループ開発への橋渡し・質問受付 | — |

## 各スライドが持つべき情報（Agent向けメモ）

`slides.md` の各スライドは HTML コメントで以下を保持しています。

- `note:` — 発表者向けのスピーカーノート（話す内容の要点）
- `source:` — このスライドの内容の裏取り先ドキュメント（発表直前の fact-check 対象）
- `todo:` （ある場合のみ）— 発表者が当日までに埋めるべき実データ（会場名・グループ数など未確定値）

これにより、スライド生成エージェントが「本文として描画する情報」と
「発表者が参照する裏情報」を混同せずに扱えます。
