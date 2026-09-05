# events-slide-src

LC-Cloud 合宿（オンボーディング〜全体講習パート）のスライドです。
「スライドを作る Agent はどういう情報の持ち方を期待するのか」を Web 調査した上で、
その調査結果に沿った形式で `slides.md`（下書き）を作り、そこから実際に発表で使う
`deck.html`（ブラウザでそのまま発表できるスライドショー）を構築しました。
内容自体は既存の設計ドキュメント（`documents/terraform/`）とリポジトリ実装
（`terraform/`）を事実源としています。

**この `.md` 群（`outline.md`・`schedule.md`・`slides.md`）は配布物ではありません。**
制作用の内部メモ・下書きとして残しているだけで、当日参加者に渡すのは
`deck.html`（Artifactとして公開したもの）1本です。そのため `deck.html` は
これらの `.md` ファイルを参照しなくても単体で完結する内容になっています。

## 調査結果：Agentがスライドを持つ情報設計

Web調査で確認できた、実際に使われている2系統の代表的な規約を比較しました。

### 1. Marp（Markdown Presentation Ecosystem）

Markdown からスライドを直接レンダリングするデファクトスタンダード。
[公式ディレクティブ仕様](https://github.com/marp-team/marp/blob/main/website/docs/guide/directives.md)
によると：

- 先頭の `---` で囲んだ YAML ブロックが **フロントマター**（`theme`・`paginate`・
  `size`・`header`・`footer`・`backgroundColor` 等のデッキ全体設定）。
- 本文中の `---` が**スライドの区切り**。global directive はそれ以降全スライドに
  継承され、`_` prefix を付けた local directive（例: `_backgroundColor`）は
  そのスライド1枚だけに適用される。
- 見出し（`#`/`##`）がスライドタイトル、箇条書きが本文になる。

### 2. Anthropic 公式 `pptx` Skill（`anthropics/skills`）が使う往復表現

Claude 自身が pptx を読み書きする際の
[SKILL.md](https://github.com/anthropics/skills/blob/main/skills/pptx/SKILL.md) を確認すると、
Marp とは異なる規約を採用している：

- 既存デッキを読むときは `markitdown` で pptx → markdown 変換し、
  **`<!-- Slide number: N -->` という HTML コメントを区切りにした
  「1スライド = 1ブロック」** の形にする（YAML フロントマターは使わない）。
- スピーカーノートは本文中のテキストボックスに書かず、
  `slide.addNotes("...")` 相当の**別チャンネル**として扱う
  （本文と発表者ノートを混在させない）。
- 新規作成時はまずテンプレートのレイアウトを選び、そこにセクション単位で
  コンテンツをマッピングしてから pptx を生成する。

### 収束するポイント

系統が違っても、実務で使われる規約は次の3点に収束していた。

1. **1スライド=1ブロック**を明示的な区切り（`---` か `<!-- Slide N -->`）で作る。
   境界を曖昧にすると、下流のエージェントがどこでスライドを割るか
   自己判断してしまい、意図と違う分割をされやすい。
2. **見出し=タイトル、箇条書き=本文**という単純な対応を崩さない。
   複雑な入れ子構造・表の多用は、下流のレンダラ／エージェントが
   ページ内に収まる分量へ自動で要約・再配置する際の妨げになる。
3. **本文と「本文には出さない情報」を別チャンネルで持つ**。
   発表者ノート・参照元・後で埋める実データは、本文と同じ場所に書かず
   HTML コメントなど別扱いにする（Marp のノート記法、pptx skill の
   `addNotes` はいずれもこの原則）。

この3点を満たしつつ、人間が直接プレビュー・編集しやすい Marp 形式
（フロントマター + `---` 区切り + HTML コメントノート）を採用しました。
Marp の1スライドブロックは見出し・箇条書き・HTMLコメントノートという
単純な構造なので、そのまま `anthropics/skills` の pptx skill（や同種の
スライド生成エージェント）に渡しても「1ブロック=1スライド」「見出し=タイトル」
「コメント=ノート」の変換規則1つで機械的にマッピングできる。

## ファイル構成

| ファイル | 役割 |
| --- | --- |
| `README.md` | 本ファイル。設計方針の説明 |
| `outline.md` | スライド構成の一覧表（狙い・想定時間・情報源ドキュメント）※内部メモ |
| `schedule.md` | 合宿スケジュール・注意事項の原本データ ※内部メモ |
| `slides.md` | Marp形式のスライド下書き ※内部メモ |
| `deck.html` | **実際に配布・発表するスライド本体**（Artifactとして公開） |

## 情報源

- `README.md`（リポジトリ直下）— 管理対象・使用ツール・ロール一覧
- `documents/terraform/01-overview.md` — 設計原則・ツール選定
- `documents/terraform/12-openstack-resources.md` — OpenStack 3層アクセスモデル・モジュール一覧
- `documents/terraform/13-operation-layers.md` — Terraform / Middleware API / GitOps の役割分担
- `documents/terraform/14-middleware-architecture.md` — 今回作ってもらう「Middleware API」の設計
- `documents/terraform/16-implementation-phases.md` — 実装フェーズの進捗（Phase 0〜9）

内容は 2026-09-05 時点のリポジトリ state に基づきます。Phase 進捗（特に
Phase 5 / Phase 6 の完了状況）は当日までに変わる可能性があるので、
発表直前に `16-implementation-phases.md` の該当 Phase を再確認してください。

## 調査ソース（形式選定の根拠）

- [Marp: Markdown Presentation Ecosystem](https://marp.app/)
- [marp-team/marp — directives.md（公式ディレクティブ仕様）](https://github.com/marp-team/marp/blob/main/website/docs/guide/directives.md)
- [anthropics/skills — pptx/SKILL.md（Claude公式のpptx読み書きスキル）](https://github.com/anthropics/skills/blob/main/skills/pptx/SKILL.md)
- [HTML vs Markdown for AI Agents: Which Format Wins in 2026 — beam.ai](https://beam.ai/agentic-insights/html-vs-markdown-which-format-actually-makes-ai-agents-more-useful)
- [In Agentic AI, It's All About the Markdown — Visual Studio Magazine](https://visualstudiomagazine.com/articles/2026/02/24/in-agentic-ai-its-all-about-the-markdown.aspx)
- [AI Skill PPT Generators in 2026: Is SKILL.md the New Standard? — presenti.ai](https://presenti.ai/blog/ai-skill-ppt-generator-landscape/)
