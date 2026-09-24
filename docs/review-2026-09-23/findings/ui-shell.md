# UI 比較: シェル (ホーム / ナビ / フッター / 静的ページ / 共通部品 / HTTP) — ID 接頭辞 SHELL

## 担当範囲の要約

- 対象: `/` (ホーム), ナビバー, フッター, 全体の見た目 (Bootstrap 3.2.0 → 5.3.3), `/publications` `/agents` `/demo` `/not_found` `robots.txt` `llms.txt` `.well-known/mcp.json`, 共通部品 (Tutorial ドロップダウン, ⓘ ヘルプ, copy ボタン, ゲノムタブ, サービス状態表示), HTTP レベルの挙動。5 つの解析ツール本体・検索・/view の中身は対象外。
- 方法: 本番と localhost:9292 の両方を `curl` で取得し、タグを落としたテキストを `diff`。挙動は HAML/ERB/JS/TS ソースで確認。ブラウザ操作は行っていない。
- 全 44 項目。内訳: 改良 11 / 単なる変更 20 / 機能削除 3 / **退行 (要修正) 7** / データ差分 2 / 新機能 1。
- 文言・構造の大枠 (ナビ項目の並び、フッター文言、Tutorial の URL、404 の本文、robots.txt) は本番と一致していることを確認済み。navbar の略称切替 (1375px) も同一。
- 要修正の中心は Markdown レンダラ差 (redcarpet → kramdown) による **裸 URL の非リンク化 (SHELL-20)**、AI エージェント向け文書 3 件+openapi の **TAIR10 誤記 (SHELL-25)** と **`/api/colo` 例の誤り (SHELL-27)**、ⓘ ヘルプの **改行消失 (SHELL-34)**、Enrichment Analysis の **事前稼働チェック消失 (SHELL-39)**、本番ホームに手で追記された **Diff Analysis 停止告知の未移植 (SHELL-02)**。
- 重要な事実: 本番の `updates.markdown` はリポジトリ master の内容と異なる (サーバ上で直接編集されている)。他の Markdown (publications/agents/demo) はリポジトリと一致。
- ナビの "Agents" 項目削除は commit 0c66277 (2026-09-15) で「per request」と明記された意図的変更。
- 本番は `http://chip-atlas.org/` を 200 で配信 (HTTPS へリダイレクトしない)。新 nginx 設定は 301 を返す。

---

## ホーム `/`

### SHELL-01 実験数の表示: 433,000 → 454,000
- **ページ/機能**: Home > page-header のリード文 "A data-mining suite ... integrating N ChIP-seq, ATAC-seq and Bisulfite-seq experiments."
- **旧 (chip-atlas.org)**: `433,000` (実験 ID のユニーク数を 1,000 単位に切り捨て、カンマ区切り)
- **新 (localhost:9292)**: `454,000` (同じ切り捨て規則。`/api/stats` は `total_experiments: 454476`, `total_experiments_formatted: "454,000"`)
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:70, old-app/lib/pj/experiment.rb:245-248, https://chip-atlas.org/ (本文 "433,000") / 新: lib/models/experiment.rb:82-86, :197-199, routes/pages.rb:15-19, curl `/` および `/api/stats`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新 DB (database.sqlite.verify) は hg19/mm9/dm3/ce10 を除き TAIR12 を含むため単純比較不可。表示規則 (切り捨て・カンマ) は同一。新版は `frontend/pages/homepage.ts:6-19` がロード後に `/api/stats` を再取得して `#experiment-count` を上書きするが、同じ DB から同じ値が返るため見た目の変化はない (無駄なリクエストが 1 本増えるだけ)。

### SHELL-02 本番ホーム限定の赤字告知「Diff Analysis is temporarily unavailable…」が新版に無い
- **ページ/機能**: Home > "What's new" リスト先頭
- **旧 (chip-atlas.org)**: 先頭に `<span style="color:red"><strong>Diff Analysis is temporarily unavailable due to the backend server issue. We are sorry for the inconvenience.</strong></span>` が表示される。この行はリポジトリ master の `old-app/views/updates.markdown` には存在せず (そこには HTML コメント化された Enrichment analysis 停止告知の残骸のみ)、本番サーバ上のファイルが直接編集されている。
- **新 (localhost:9292)**: `views/updates.markdown` は旧リポジトリと同一内容。告知行は無く、HTML コメント `<!-- - <span style="color:red">**Enrichment analysis will be temporarily unavailable ...** -->` がそのまま HTML に出力される (画面には出ない)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: https://chip-atlas.org/ (レンダリング結果 `<li><span style="color:red">…`), old-app/views/updates.markdown:3 / 新: views/updates.markdown:3, views/about.erb:117-121, curl `/`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新版の `/status` は `features.diff_analysis: "unavailable"` を返し、Diff Analysis ページ自体は `/jobs/available` を見てインライン通知+ボタン無効化を行う (SHELL-40)。しかしホームには何も出ない。切替時に本番の告知文を移植するか、ホームが `/status` を読んで告知を自動表示する仕組みにするのが望ましい。運用上「サーバ上で markdown を直接編集する」慣行があることを、新版のデプロイ手順 (docker イメージ) で考慮する必要がある。

### SHELL-03 "What's new" の記号・見出し id・コメント出力
- **ページ/機能**: Home > "What's new"
- **旧 (chip-atlas.org)**: `<h3>What&#39;s new</h3>`、本文の `'peak'` は直引用符。見出しに id 無し。
- **新 (localhost:9292)**: `<h3 id="whats-new">What’s new</h3>` (kramdown のスマートクォートで `'` → `’`)、`‘peak’`。HTML コメントが本文中に出力される。リスト各行の文言は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/about.haml:144 (redcarpet, autolink) / 新: views/about.erb:119 (`Kramdown::Document ... input: 'GFM'`), curl `/`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 見出し id は `#whats-new` へのリンクを可能にする副次的改善。

### SHELL-04 "What's new" ブロックの横位置 (オフセット 2 → 1 カラム)
- **ページ/機能**: Home > "What's new" のグリッド配置
- **旧 (chip-atlas.org)**: `.col-md-10.col-md-offset-2` (左に 2/12 = 16.7% の空き)
- **新 (localhost:9292)**: `.col-md-10.offset-md-1.markdown-content` (左に 1/12 = 8.3%)
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/about.haml:143 / 新: views/about.erb:118
- **確認方法**: `ソース推定` (`要ブラウザ確認` で見た目の差を確認)
- **備考**: 意図の記録は見当たらない。旧の 2 カラムはタイル行との揃えが目的だった可能性がある。

### SHELL-05 機能タイル (6 枚) の実装: FontAwesome + JS 高さ揃え → SVG + CSS flex
- **ページ/機能**: Home > Peak Browser / Enrichment Analysis / Diff Analysis / Target Genes / Colocalization / Dataset Search のタイル
- **旧 (chip-atlas.org)**: 見出し・バッジ (ChIP/ATAC/Bisulfite)・リンク先は新旧同一。`<i class="fas fa-glasses">` 等の FA アイコン 70px。`.jumbotron` 内は `.row > .col-xs-12.col-sm-4 / .col-sm-8`。高さは `pj.js` の `setJumbotronHeight()` で最大値に揃える。`.row.align-height { display:flex; flex-direction:row }` に `flex-wrap` が無いので、<992px (col-md 無効) では 3 枚が 1 行に押し込まれる (推定)。
- **新 (localhost:9292)**: `/icons/chip-atlas.svg#glasses` 等のスプライト (`.icon-lg` 70px)。`.jumbotron { display:flex; align-items:center; height:100% }`、`.align-height { flex-wrap:wrap }`、<768px でアイコン上・ラベル下に縦積み。JS 不要。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/about.haml:34-141, old-app/public/js/pj/pj.js:9-17, old-app/views/style.sass:38-75 / 新: views/about.erb:13-115, public/css/style.css:376-430, views/_icon.erb
- **確認方法**: `ソース推定` (`要ブラウザ確認`: 旧のモバイル表示、新の等高)
- **備考**: 背景色 #eee、角丸 6px、padding 30/30/30/40px、`.label-primary` #428bca は style.css で BS3 の値を再現している (BS5 には `.jumbotron`/`.label` が無いため自前定義)。

### SHELL-06 ホームのリード文のマークアップ
- **ページ/機能**: Home > page-header
- **旧 (chip-atlas.org)**: `<p>` (BS3 既定 margin 0 0 10px)。ナビ・タイルのリンクは `app_root` による絶対 URL (`https://chip-atlas.org/peak_browser`)。
- **新 (localhost:9292)**: `_page_header.erb` 経由で `<p class="main-desc">` (line-height 150%, margin-bottom 0 → 罫線までの余白が 10px 減る)。実験数は `<span id="experiment-count">` で包む。リンクは相対 (`/peak_browser`)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/about.haml:27-32, old-app/app.rb:26-28 / 新: views/about.erb:6-11, views/_page_header.erb:13-29, public/css/style.css:364-367
- **確認方法**: `curl+ソース確認済み`

---

## ナビバー

### SHELL-07 ナビの "Agents" 項目 (アイコン robot, 略称 "API") が削除された
- **ページ/機能**: Navbar > 7 番目の項目
- **旧 (chip-atlas.org)**: Peak Browser / Enrichment Analysis / Diff Analysis / Target Genes / Colo / Publications / **Agents** / Docs の 8 項目。`/agents` 表示時は Agents がアクティブ (#080808)。
- **新 (localhost:9292)**: Agents を除く 7 項目。`/agents` `/demo` は配信されるが、ナビ・フッター・ホームのどこからもリンクされない (`views/*.erb` に `/agents` へのリンク無し)。`/agents` は llms.txt と `/demo` 本文から、`/demo` は `/agents` 本文からのみ到達可能。`@active_menu = 'agents'` は設定されるが対応項目が無いので何も強調されない。スプライトには `robot` が残っている (未使用)。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: old-app/views/_navigation.haml:43-47, https://chip-atlas.org/agents (`<li class="active">`) / 新: views/_navbar.erb:10-60, views/agents.erb:4, git commit 0c66277 ("Removed Agents and Demo from the navbar per request. Both routes still serve")
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的 (コミットメッセージに明記)。ただし人間ユーザがエージェント向け API 文書に辿り着く導線が無くなるので、フッターか Docs 付近に "API" リンクを 1 つ置く価値はある。"Demo" は旧ナビにも無かった (差分なし)。

### SHELL-08 ID ジャンプ欄の初期値: ランダム (GSM469863 / SRX018625) → 固定 SRX018625
- **ページ/機能**: Navbar > "ID: [ ] Go"
- **旧 (chip-atlas.org)**: サーバ側で `["GSM469863", "SRX018625"].sample` → ページ読込ごとに GSM か SRX のどちらかが入る (GSM ID も受け付けることの暗黙のデモ)。
- **新 (localhost:9292)**: 常に `SRX018625`。`aria-label="Experiment ID"` 付き。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/_navigation.haml:60-61 / 新: views/_navbar.erb:65-66
- **確認方法**: `curl+ソース確認済み`

### SHELL-09 ID ジャンプの送信挙動 (エンコード・エラー応答)
- **ページ/機能**: Navbar > ID フォーム送信 → `/view?id=…`
- **旧 (chip-atlas.org)**: `pj.js` がボタン click を横取りし `window.open("/view?id=" + expid)` (エンコード無し、trim 無し。`initResponsiveNavbar` の trim 付き submit ハンドラは click の preventDefault で到達しない)。404 ページには pj.js が無く、同等のインライン script。サーバ側: 空 ID → 404、`gsm469863` → 302 → `/view?id=SRX018625`、未知の GSM (`GSM1`) → **302 → `/view?id=`** → 404 (2 ホップ)、`/view` (id 無し) → **500**。
- **新 (localhost:9292)**: `<form onsubmit>` で `window.open('/view?id=' + encodeURIComponent(value))` (全ページ共通、JS モジュール不要)。空 → 404、小文字 GSM → 302 → SRX、未知 GSM → 直接 404、id 無し → **400 JSON**。前後空白は新旧とも trim されず 404。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/pj.js:21-27, :49-58, old-app/views/not_found.haml:50-55, old-app/app.rb:260-268, curl `https://chip-atlas.org/view?id=GSM1` (302 Location `/view?id=`), `/view` (500) / 新: views/_navbar.erb:62-68, routes/pages.rb:27-34, curl `/view?id=` `/view?id=GSM1` `/view?id=%20SRX018625%20` `/view`
- **確認方法**: `curl+ソース確認済み` (新規タブで開く挙動は `要ブラウザ確認`)
- **備考**: 新旧とも新規タブ (`window.open`)。`value.trim()` を入れると空白混入時の 404 を防げる。

### SHELL-10 ナビ右側 (Search リンク + ID フォーム) のレイアウトと部品の見た目
- **ページ/機能**: Navbar 右端
- **旧 (chip-atlas.org)**: `p.navbar-text.navbar-right` (Search) / `form.navbar-form.navbar-right` / `p.navbar-text.navbar-right` ("ID:") の float 配置。視覚順は左から "ID: [入力] Go  Search"。"ID:" は `.navbar-inverse .navbar-text` の灰色 (#777)、Go は `.btn.btn-default` (白地 #333 文字、14px、高さ 34px)。新版 CSS のコメントと docs/ui-parity-audit-2026-09-14.md:136 によれば本番はこの右側が 2 行目に折り返し、ナビ全体が約 72px 高になる (要ブラウザ確認)。
- **新 (localhost:9292)**: `.navbar-right-stack` (flex row, gap 14px) に "ID: [入力] Go" と "Search" を 1 行で配置 (視覚順は同じ)。"ID:" は `text-light` (#f8f9fa)、Go は `.btn-light.btn-sm` (14px)、入力欄は `.form-control-sm`。<992px ではメニュー内で縦積み。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/_navigation.haml:53-65, prod bootstrap.min.css (`.navbar-inverse .navbar-text{color:#777}`, `.btn-default{color:#333;background-color:#fff;border-color:#ccc}`) / 新: views/_navbar.erb:61-74, public/css/style.css:308-334, :336-350
- **確認方法**: `ソース推定`、`要ブラウザ確認` (本番の 2 行折返しの有無、幅 1376〜1600px 帯での挙動)
- **備考**: 意図的に 1 行化した旨が style.css:308-312 に記載。

### SHELL-11 モバイル折りたたみの閾値: <768px → <992px
- **ページ/機能**: Navbar > ハンバーガー化
- **旧 (chip-atlas.org)**: Bootstrap 3 `navbar-toggle` (`data-toggle="collapse"`, 3 本線 `icon-bar`) — 768px 未満で折りたたみ。768〜991px は横 1 行 (略称表示)。
- **新 (localhost:9292)**: Bootstrap 5 `navbar-expand-lg` + `navbar-toggler` (`data-bs-toggle`) — 992px 未満で折りたたみ。`aria-controls`/`aria-label` 付き。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/_navigation.haml:1-11 / 新: views/_navbar.erb:1-9, public/css/bootstrap5.min.css (`.navbar-expand-lg` @ 992px)
- **確認方法**: `ソース推定`、`要ブラウザ確認`
- **備考**: 折りたたみメニュー内でも `.abbrev-text` (PB/EA/DA/TG/Colo/Pub/Doc/?) が出るのは新旧共通 (1375px 以下の規則がそのまま効く)。旧では 768px 未満のみだったこの状態が、新では 768〜991px でも起きる。モバイルのメニューではフル表記の方が分かりやすい。

### SHELL-12 ナビの外観再現とその残差 (背景・アイコン・余白・ブランド)
- **ページ/機能**: Navbar 全体
- **旧 (chip-atlas.org)**: `navbar-inverse navbar-fixed-top` (背景 #222, active #080808, リンク白)。ブランドは `fa-mountain` (18px)。`.container-fluid { padding: .25em 5em }` (=70px)、1375px 以下で `.25em 1em`。項目アイコンは FA。Docs は `fab fa-github`。
- **新 (localhost:9292)**: `navbar-dark bg-dark fixed-top` に `--ca-navbar-bg:#222`、active #080808、リンク #fff を上書きして再現。ブランドは SVG `mountain` (20px) に `aria-label="ChIP-Atlas home"`、href は `/`。左右 padding 70px は 992px まで維持 (旧は 1375px 以下で 14px)。項目順・文言・略称・Docs の wiki URL は同一。`.navbar .nav-link i` の規則は `<i>` が無いため死んでいる。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/style.sass:2-3, :27-32, :259-302, prod bootstrap.min.css (`.navbar-inverse{background-color:#222;border-color:#080808}`) / 新: public/css/style.css:4-40, :54-88, :119-142, :303-306, :336-350, views/_navbar.erb:3-5
- **確認方法**: `curl+ソース確認済み` (色は `要ブラウザ確認`)
- **備考**: 992〜1375px の帯では新版の方がナビ内側の余白が 56px 広い。

---

## フッター

### SHELL-13 フッター: 文言・リンク先は同一、属性が追加
- **ページ/機能**: Footer (ロゴ 6 件、謝辞、ライセンス、保守情報、連絡先)
- **旧 (chip-atlas.org)**: 熊本大 / DDBJ / NBDC / JST / DBCLS / 千葉大 のロゴ (JST と千葉大は 150px、他 100px)、"This work is supported by NIG Supercomputer system and JST NBDC JPMJND2202."、CC-BY 4.0 と publication へのリンク、"NIG Supercomputer system maintenance information." (target=_blank)、GitHub issues、`mailto:okishinya@kumamoto-u.ac.jp?cc=zou@kumamoto-u.ac.jp`。`<row>` という不正要素でラップ。`<img>` に alt 無し。
- **新 (localhost:9292)**: 全リンク先・文言・順序・ロゴ幅が同一。`<div class="row"><div class="col-12">` に修正。全 `target="_blank"` に `rel="noopener noreferrer"`、全 `<img>` に `alt` を追加。CSS (margin-top 10em, uppercase, italic, 66%) も同一値。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/footer.haml:1-55, old-app/views/style.sass:179-219 / 新: views/_footer.erb:1-63, public/css/style.css:91-117, :144-157; ロゴ画像は新旧とも 200 (curl `/images/logo/jst_logo.png`)
- **確認方法**: `curl+ソース確認済み`

---

## 全体の見た目 (Bootstrap 3.2.0 → 5.3.3)

### SHELL-14 本文リンクに下線が付く
- **ページ/機能**: 全ページの `<a>` (フッター、What's new、/publications の約 1,400 件の "Link"、/agents /demo の本文リンク)
- **旧 (chip-atlas.org)**: BS3 `a{color:#428bca;text-decoration:none}` — hover 時のみ下線。
- **新 (localhost:9292)**: BS5 `a{...;text-decoration:underline}` — 常時下線。style.css はリンク色 (#428bca / hover #2a6496) は再現しているが `text-decoration` を上書きしていない (`.navbar-brand`、`.nav-link`、`.btn` は BS5 側で none)。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: prod bootstrap.min.css `a{color:#428bca;text-decoration:none}` / 新: public/css/bootstrap5.min.css `a{color:rgba(var(--bs-link-color-rgb),...);text-decoration:underline}`, public/css/style.css:17-19 (色のみ)
- **確認方法**: `ソース推定` (`要ブラウザ確認`)
- **備考**: 「現在の UI の見た目を保つ」方針なら `a { text-decoration: none } a:hover { text-decoration: underline }` を style.css に足すだけで揃う。/publications の見た目の印象がもっとも変わる箇所。

### SHELL-15 見出しサイズ・行間・字間
- **ページ/機能**: 全ページの h1〜h4
- **旧 (chip-atlas.org)**: h1 36px / h2 30px / h3 24px / h4 18px、line-height 1.1、margin 20px 0 10px、`h1, h2 { letter-spacing:-1px }` (全体)。
- **新 (localhost:9292)**: BS5 は rem 基準 (html 16px) で h1 40px / h2 32px / h3 28px / h4 24px (≥1200px)、line-height 1.2、margin 0 0 .5rem。`--bs-body-font-size:14px` は body にしか効かないので見出しは大きくなる。`.jumbotron h3` のみ 24px に固定。letter-spacing -1px は `.page-header h1` のみ (h2 と 404 の h1 は無し)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: prod bootstrap.min.css (`h1,.h1{font-size:36px}` 等), old-app/views/style.sass:5-7 / 新: public/css/bootstrap5.min.css (`.h1,h1{font-size:2.5rem}` `.h3,h3{font-size:1.75rem}` `.h4,h4{font-size:1.5rem}`), public/css/style.css:15-23, :359-362, :402
- **確認方法**: `ソース推定` (`要ブラウザ確認`)
- **備考**: /publications の h2 「To cite ChIP-Atlas…」、ホームの h3 「What's new」、404 の h1 が旧より一回り大きい。

### SHELL-16 ボタン・入力欄の寸法と角丸
- **ページ/機能**: 全ページの `.btn` `.form-control` (Tutorial ボタン、Go、各ツールの送信ボタン)
- **旧 (chip-atlas.org)**: `.btn` 14px、padding 6px 12px、角丸 4px。`.form-control` 14px、高さ 34px、角丸 4px。
- **新 (localhost:9292)**: `.btn` 16px (1rem)、padding 6px 12px、角丸 6px (.375rem)。`.form-control` 16px、padding .375rem .75rem (高さ約 38px)。`.btn-primary` の色 (#428bca/#357ebd, hover #3276b1) は BS3 値を再現。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: prod bootstrap.min.css `.btn{...font-size:14px...}` `.form-control{...height:34px;...font-size:14px...}` / 新: public/css/bootstrap5.min.css `.btn{--bs-btn-font-size:1rem...}` `.form-control{...font-size:1rem...}`, public/css/style.css:26-31
- **確認方法**: `ソース推定` (`要ブラウザ確認`)

### SHELL-17 コンテナ幅・ガター・上部余白
- **ページ/機能**: 全ページのレイアウト
- **旧 (chip-atlas.org)**: `.container` 1170 / 970 / 750px (≥1200 / ≥992 / ≥768)、左右 padding 15px、行ガター 30px。`body { padding-top: 70px }`。
- **新 (localhost:9292)**: `.container.container-narrow` 1170 (≥1200、style.css で BS5 の 1140/1320 を上書き) / 960 / 720 / 540px (≥576)、padding 12px、ガター 24px。`body { padding-top: calc(50px + 10px) }` = 60px。`.page-header` (padding-bottom 9px, margin 40px 0 20px, 罫線 #eee) は BS3 値を再現。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: prod bootstrap.min.css (`@media (min-width:992px){.container{width:970px}` 等), old-app/views/style.sass:14-15 / 新: public/css/style.css:43-51, :286-290, :353-357, public/css/bootstrap5.min.css (`.container ... max-width:960px` 等, `--bs-gutter-x:1.5rem`)
- **確認方法**: `ソース推定`

### SHELL-18 `<head>`: title / description / meta の差
- **ページ/機能**: 全ページの `<title>` `<meta>`
- **旧 (chip-atlas.org)**: `/publications` は `ChIP-Atlas: Publication` (単数)。`/agents` description "Guide for AI agents to use ChIP-Atlas MCP tools and API endpoints."、`/demo` "...via llms.txt, MCP server, and HTTP API."、404 "We provide cute pics instead."。`<meta http-equiv="X-UA-Compatible" content="IE=edge">` あり。favicon の `<link>` は無く `/favicon.ico` は 404。`lang="en"`、viewport は同一。
- **新 (localhost:9292)**: `ChIP-Atlas: Publications` (複数)。`/agents` "Guide for AI agents to query ChIP-Atlas via its HTTP API."、`/demo` "...via llms.txt and the HTTP API."、404 "Page not found."。X-UA-Compatible 無し。favicon は同様に無し (404)。ホーム・publications の title/description、author、lang、viewport は同一。description 未設定ページ用の既定文 "Browse and analyse public ChIP-Seq/DNase-Seq/ATAC-Seq/Bisulfite-Seq data." が layout に追加。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/publications.haml:11, agents.haml:8, demo.haml:8, not_found.haml:8, about.haml:5 / 新: views/layout.erb:2-8, views/publications.erb:2-3, agents.erb:2-3, demo.erb:2-3, not_found.erb:2-3; curl で各 `<title>` を比較、`/favicon.ico` は新旧とも 404
- **確認方法**: `curl+ソース確認済み`

### SHELL-19 アセット配信: FontAwesome/jQuery/BS3 → BS5 バンドル + SVG スプライト、キャッシュバスティング
- **ページ/機能**: 全ページの CSS/JS 読み込み
- **旧 (chip-atlas.org)**: `bootstrap.min.css` + `/style.css` (リクエスト毎に `sass` で `style.sass` をコンパイル、キャッシュヘッダ無し) + `fontawesome.css` `brands.css` `solid.css` (+ agents/demo は `regular.css`) + webfonts。JS は jQuery + bootstrap.min.js + `pj/*.js`。
- **新 (localhost:9292)**: `bootstrap5.min.css` + `/css/style.css` の 2 本、いずれも `?v=<mtime>` 付き (nginx `expires 1d` と両立)。アイコンは `/icons/chip-atlas.svg` の `<use>` 参照 (27 個収録、必要な mountain/glasses/hand-holding-heart/balance-scale-left/bullseye/compress-arrows-alt/book/github/search/question-circle/info-circle を確認)。JS は `bootstrap.bundle.min.js` + ページ別 ES module (`type="module"`)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/about.haml:13-20, :151-153, old-app/app.rb:109-111 / 新: views/layout.erb:9-10, :18-21, app.rb:38-42, public/icons/chip-atlas.svg, config/nginx/chip-atlas.conf:26-36
- **確認方法**: `curl+ソース確認済み`
- **備考**: `type="module"` は defer 相当なので、JS 無効/失敗時もサーバ描画部分 (ホーム、静的ページ、ナビの ID ジャンプは inline onsubmit) は動く。ゲノムタブ等は JS 必須 (SHELL-38)。

---

## 静的ページ (/publications, /agents, /demo, /not_found, robots.txt, llms.txt, mcp.json)

### SHELL-20 裸の URL が自動リンクされなくなった (redcarpet autolink → kramdown GFM)
- **ページ/機能**: `/publications` 冒頭 "To cite ChIP-Atlas in your publication" の 4 件 (NAR 2024 / NAR 2022 / EMBO Rep 2018 の DOI と `https://chip-atlas.org`)、`/demo` 「Here is the documentation for ChIP-Atlas: https://chip-atlas.org/llms.txt」
- **旧 (chip-atlas.org)**: `markdown(..., autolink: true)` により `<a href="http://dx.doi.org/10.1093/nar/gkae358">http://dx.doi.org/10.1093/nar/gkae358</a>` としてクリック可能。
- **新 (localhost:9292)**: kramdown (`input: 'GFM'`) は裸 URL をリンク化しないため、プレーンテキスト。引用文献 4 件の DOI が押せない。`[Link](…)` 形式の約 1,400 件は無事。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/views/publications.haml:29, old-app/views/demo.haml:30, https://chip-atlas.org/publications (先頭 `<li>` に `<a href="http://dx.doi.org/...">`) / 新: views/publications.erb:8, views/demo.erb:8, views/publications.markdown:4-8, views/demo.markdown:21, curl `/publications` (先頭 `<li>` に `<a>` 無し)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 修正案は 2 つ: (a) markdown 側を `[URL](URL)` 形式に書き換える (4+1 箇所)、(b) `Kramdown::Document.new(..., input: 'GFM', gfm_autolink: true)` (kramdown-parser-gfm ≥1.1 のオプション)。(b) は動作確認が必要。

### SHELL-21 スマートクォート変換 (`'` → `’`, `"` → `“ ”`)
- **ページ/機能**: `/publications` (約 20 件の論文タイトル: Crohn's, Alzheimer's, "hit-and-run", 3'-end 等)、`/demo` (You'll, What's, "Question" の引用符、Tips の "Histone" 等)、ホーム What's new
- **旧 (chip-atlas.org)**: 直引用符のまま。
- **新 (localhost:9292)**: kramdown の typographic 変換で曲引用符になる。コード内・リンク内は変換されない。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: diff of stripped `/publications` (54 行中ほぼ全てがこの差), `/demo`; 新: views/publications.erb:8 (`smart_quotes` を無効化していない)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 論文タイトルの正確性を重視するなら `smart_quotes: []` (kramdown オプション) で無効化できる。

### SHELL-22 単語内アンダースコアが誤って強調されなくなった
- **ページ/機能**: `/publications` 2025 年 Wang, Z. の項目 "Hsa_circ_0038737 promotes PARPi resistance…"
- **旧 (chip-atlas.org)**: redcarpet が `_circ_` を強調と解釈し `Hsa<em>circ</em>0038737` と表示 (本番のバグ)。
- **新 (localhost:9292)**: `Hsa_circ_0038737` と正しく表示。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: diff of stripped `/publications` 行 286/288; https://chip-atlas.org/publications
- **確認方法**: `curl+ソース確認済み`

### SHELL-23 見出しに id が付与され、アンカーリンクが可能に
- **ページ/機能**: `/publications` (2 件)、`/agents` (15 件)、`/demo` (11 件)、ホーム What's new (1 件)
- **旧 (chip-atlas.org)**: 見出しに id 無し (0 件)。
- **新 (localhost:9292)**: `<h2 id="to-cite-chip-atlas-in-your-publication">`、`<h2 id="api-basics">`、`<h2 id="1-quick-start-llmstxt">` 等。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: curl 結果 (`grep -c '<h[1-6] id='`: local 2/15/11、prod 0/0/0)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧では publications.haml が `tables:` を有効化していなかったが、テーブルは存在しないため影響なし。リストの入れ子構造は新旧同一。

### SHELL-24 `/agents` の内容: MCP 中心 → HTTP API 中心に全面改訂
- **ページ/機能**: `/agents` 本文
- **旧 (chip-atlas.org)**: 「MCP Server」節 (インストール・Claude Desktop 設定・`CHIP_ATLAS_BASE_URL`・ソースへのリンク)、「Tools Reference」(10 ツール)、「HTTP API Endpoints」(`/data/*`、`POST /download`)。データモデルは agClass/agSubClass/clClass/clSubClass、Q 値 "1, 5, 10, 50, 100"、ID は "SRX or GSM"。
- **新 (localhost:9292)**: 「API Basics」(`/api/` プレフィクス、snake_case、`{id,label,count}`)、「Endpoint Reference」(Classification / Experiments / Analysis indexes / Result data and downloads / Jobs)、Tips。冒頭に openapi.yaml と llms.txt へのリンク。Q 値 "05, 10, 20, 50"、ID は "SRX, ERX, or DRX"、CUT&Tag/CUT&RUN を明記。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: `diff old-app/views/agents.markdown views/agents.markdown`, stripped diff of `/agents` (338 行)
- **確認方法**: `curl+ソース確認済み`
- **備考**: MCP 廃止自体は意図的 (BRIEF)。誤記は SHELL-25/27 に分離。

### SHELL-25 エージェント向け文書の "TAIR10" 誤記 (実データは TAIR12)
- **ページ/機能**: `/agents` Data Model 表、`/demo` 冒頭、`/llms.txt` 2 箇所、`/openapi.yaml` 2 箇所
- **旧 (chip-atlas.org)**: A. thaliana 自体が無い。
- **新 (localhost:9292)**: 文書は "hg38, mm10, rn6, dm6, ce11, sacCer3, **TAIR10**" と書くが、`config/genomes.yml` と `/api/genomes` は `TAIR12` ("A. thaliana (TAIR12)")。`/api/genomes` に TAIR10 は存在しないため、文書どおりに `genome=TAIR10` を投げたエージェントは空結果か 400 を受ける。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 新: views/agents.markdown:26, views/demo.markdown:5, public/llms.txt:27, :63, public/openapi.yaml:126, :418, config/genomes.yml:15-16, curl `/api/genomes`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 5 ファイル 6 箇所を TAIR12 に置換するだけ。

### SHELL-26 `/demo` の内容: MCP 手順削除、curl 例を `/api/*` に更新
- **ページ/機能**: `/demo` 本文
- **旧 (chip-atlas.org)**: 「2. Setup: MCP Server」(前提・ビルド・Claude Desktop/Code 設定・Verify)、各シナリオに「With MCP tools」と「With HTTP API (curl)」の 2 本立て、`/data/*` と `POST /download` の curl、MCP troubleshooting、末尾に MCP ソースと `.well-known/mcp.json` へのリンク。「10+ genome assemblies」。
- **新 (localhost:9292)**: 「2. The HTTP API」、各シナリオは curl のみ、`/api/*` (`download_url`, `search`, `colo_index` 等)、Tips に URL エンコードと `download_url` 必須パラメータの説明、末尾は Agent Guide / OpenAPI / llms.txt。「seven genome assemblies」。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: `diff old-app/views/demo.markdown views/demo.markdown`, stripped diff of `/demo` (297 行)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 「over 1 million public … experiments」は新旧とも記載されているが実数は 45 万 (`/api/stats`)。旧からの誇張が引き継がれている。

### SHELL-27 文書中の `/api/colo` 例 (`cell_type=K-562`) が 404 になる
- **ページ/機能**: `/llms.txt` (Colocalization Data / Download の例)、`/agents` Result data 表、`/demo` シナリオ 4
- **旧 (chip-atlas.org)**: 該当なし (旧は index を返す `/data/colo_analysis.json` のみ)。
- **新 (localhost:9292)**: 例は `GET /api/colo?genome=hg38&track=CTCF&cell_type=K-562` だが、colocalization の結果ファイルは細胞型 **クラス** 単位 (`/api/colo_index?genome=hg38` の CTCF は `["Adipocyte","Blood","Bone",…]`、K-562 は index に無い)。実行すると `404 {"error":"Colocalization data not found"}`。`cell_type=Blood` なら 200。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 新: public/llms.txt:47-48, views/agents.markdown (Result data 表), views/demo.markdown (シナリオ 4), routes/api.rb:158-170, lib/services/location_service.rb:34-36, curl `/api/colo_index?genome=hg38`, `/api/colo?...cell_type=K-562` (404) / `...cell_type=Blood` (200)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 文書の例を `cell_type=Blood` に直し、「`cell_type` は細胞型クラス (index の値) を指定」と注記する。エージェントが最初に試す例が 404 になるのは体験として悪い。

### SHELL-28 404 ページ: giphy 画像の撤去、導線ボタンの追加
- **ページ/機能**: `/not_found` および未知パス
- **旧 (chip-atlas.org)**: `.col-md-10` 左寄せに `<h1><i class="fas fa-mountain"></i> ChIP-Atlas: 404</h1>`、本文 "Sorry, could not find the requested resource. Try with different data or contact us."、`<p class="gif">` に `http://api.giphy.com/v1/gifs/random?api_key=dc6zaTOxFJmzC&tag=cute%20cat%20dog` からランダム画像を jQuery で挿入。HTTPS ページからの http:// XHR は mixed content としてブロックされるため、実際には画像は出ない (推定)。
- **新 (localhost:9292)**: `.col-md-8.offset-md-2` に `<h1>ChIP-Atlas: 404</h1>` (アイコン無し)、同じ本文、"Back to Home" (btn-primary) と "Report Issue" (GitHub issues, 新規タブ) の 2 ボタン。外部リクエスト無し。ステータス 404、`x-cascade: pass` は新旧同一。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/not_found.haml:26-36, :57-71, curl `https://chip-atlas.org/nonexistent` (404) / 新: views/not_found.erb:5-14, routes/pages.rb:152-164, curl `/nonexistent` (404)
- **確認方法**: `curl+ソース確認済み` (giphy のブロックは `要ブラウザ確認`)
- **備考**: 新版は `/api/*` の未知パスには HTML ではなく JSON `{"error":"Not found"}` を返す (旧は HTML 404 ページ) — エージェント向けには改善。

### SHELL-29 robots.txt: 内容は同一だが、無効になった Disallow が残る
- **ページ/機能**: `/robots.txt`
- **旧 (chip-atlas.org)**: 496 bytes。`Disallow: /api /data /view /browse /download /wabi_chipatlas`、Crawl-delay 30、Baidu/Slurp/litefinder 120。
- **新 (localhost:9292)**: バイト単位で同一。`/data` `/browse` `/download` `/wabi_chipatlas` は新版に存在しないパス。新設の `/jobs` `/status` は未記載。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: old-app/public/robots.txt, public/robots.txt (diff 無し)
- **確認方法**: `curl+ソース確認済み`
- **備考**: `Disallow: /api` はエージェント向けに公開している `/api/*` をクローラから隠す意図として妥当だが、`/jobs` (POST 投入口) も足しておくとよい。

### SHELL-30 llms.txt の全面改訂 (旧の `/data/*` 参照は全て 404 に)
- **ページ/機能**: `/llms.txt`
- **旧 (chip-atlas.org)**: 5,345 bytes。API Endpoints は `/data/list_of_genome.json` 等 9 件 + `/qvalue_range`, `POST /download`, `POST /colo`, `POST /target_genes`, `GET /search`。MCP Server Source へのリンク。「10+ genome assemblies」。
- **新 (localhost:9292)**: 8,957 bytes。`/api/*` 20 件、`/status`、`/jobs/*` 5 件に再編。MCP 言及なし。「seven genome assemblies」、CUT&Tag/CUT&RUN 追記。新 llms.txt 中の URL を localhost に対して全件確認: `/api/colo` の例 (SHELL-27) と `/jobs/submit` (POST 専用、GET は 404) と `/jobs/:id/*` (プレースホルダ、400) 以外は 200。旧 llms.txt 中の `/data/*` 9 URL は新版で全て 404 (HTML ページ)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: old-app/public/llms.txt, public/llms.txt; curl による URL 全件チェック (本レポート作成時)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧 llms.txt をキャッシュしているエージェントは切替直後に全滅する。移行期間中は `/data/*` に JSON の 410/リダイレクト案内を返す選択肢もある (API 担当の判断事項)。

### SHELL-31 llms.txt の `/status` 説明が実装と食い違う
- **ページ/機能**: `/llms.txt` "Service status" 節
- **旧 (chip-atlas.org)**: 該当なし。
- **新 (localhost:9292)**: 文書は「The response includes `data_server`, `wabi`, `wes` **booleans** and a `feature_status` map」。実際の `/status` は `{"services":{"data_server":"ok","wabi":"ok","wes":"not_checked"},"features":{"peak_browser":"ok",…,"diff_analysis":"unavailable"}}` — 文字列値で、キー名は `services`/`features`。
- **分類**: `退行 (要修正)`
- **影響度**: 低
- **根拠**: public/llms.txt:77, routes/health.rb:27-40, curl `/status`
- **確認方法**: `curl+ソース確認済み`

### SHELL-32 `/.well-known/mcp.json` の廃止
- **ページ/機能**: MCP 自動検出メタデータ
- **旧 (chip-atlas.org)**: 200 (883 bytes、10 ツール名と `node mcp/dist/index.js` のインストール情報)。
- **新 (localhost:9292)**: 404 (HTML 404 ページ)。`mcp/` ディレクトリ自体が無い。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: old-app/public/.well-known/mcp.json, curl 両者
- **確認方法**: `curl+ソース確認済み`
- **備考**: MCP サーバ廃止に伴う意図的削除 (BRIEF)。旧 `/demo` はこのファイルへリンクしていたが新 `/demo` からは除去済み。

---

## 共通 UI 部品

### SHELL-33 Tutorial ドロップダウン: URL 同一、`div` → 実 `<button>`、メニュー右寄せ
- **ページ/機能**: Peak Browser / Enrichment / Diff / Target Genes / Colo / Search の page-header 右側
- **旧 (chip-atlas.org)**: `.button.btn.btn-primary.dropdown-toggle` は **`<div class="button …">`** (HAML の `.button`) で、`<span class="caret">`。キーボードでフォーカスできない。項目: PDF / Movie / Movie (統合TV, Japanese) (Diff と Search は PDF のみ)、全て `target="_blank"`。
- **新 (localhost:9292)**: `<button class="btn btn-primary dropdown-toggle" data-bs-toggle="dropdown">` に SVG `question-circle`。`dropdown-menu-end` で右端揃え (旧は左端揃え)。`rel="noopener noreferrer"` 追加。6 ページ全ての PDF/Movie/統合TV URL を旧と突合し完全一致 (Peak_Browser.pdf, qKNOkK-8hDo, togotv.2018.023 / Enrichment_Analysis.pdf, JBOB2PX5_-0, togotv.2019.005 / Diff_Analysis.pdf / Target_Genes.pdf, Sp9DUAuKkvQ, togotv.2018.024 / Colocalization.pdf, jhLnWNCe_No, togotv.2018.028 / Dataset_Search.pdf)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:42-56 ほか 5 ファイル / 新: views/_tutorial.erb:7-26, views/_page_header.erb:24-28, views/peak_browser.erb:12-17 ほか
- **確認方法**: `curl+ソース確認済み` (メニューの開閉位置は `要ブラウザ確認`)
- **備考**: 統合TV のリンクは新旧とも `http://doi.org/...` (https ではない)。

### SHELL-34 ⓘ ヘルプ文の改行が消える (popover に `white-space` 指定が無い)
- **ページ/機能**: Enrichment Analysis / Diff Analysis の ⓘ (`.info-btn[data-info]`)
- **旧 (chip-atlas.org)**: `alert(helpText[...])` — 文字列中の `\n` がそのまま改行として表示される (例: "Acceptable identifiers:\n  Official gene symbols (e.g. POU5F1)\n  Ensembl IDs…" の箇条書き、"Example:\n  chr1<tab>531435<tab>543845…")。
- **新 (localhost:9292)**: Bootstrap 5 Popover (`html: false`) は `textContent` で本文を入れるため、`.popover-body` (white-space: normal, max-width 276px) では `\n` が空白に潰れ、10 行超の箇条書きが 1 段落に連結される。style.css に `pre-line`/`pre-wrap` の指定は無い。テキスト自体は旧と同一 (改行文字も保持)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:183-224, :1009-1032 / 新: frontend/components/info-popover.ts:37-42, frontend/pages/enrichment-analysis.ts:31-60, frontend/pages/diff-analysis.ts:24-28, public/css/style.css (popover 規則なし), public/css/bootstrap5.min.css (`--bs-popover-max-width:276px`)
- **確認方法**: `ソース推定` (`要ブラウザ確認`)
- **備考**: `.popover-body { white-space: pre-line; max-width: 24rem }` 程度で解決。EA の「Gene list」ヘルプは約 450 文字あるので幅も広げたい。

### SHELL-35 ⓘ ヘルプの表示方式: ブロッキング `alert()` → Bootstrap popover
- **ページ/機能**: 同上 (Peak Browser の "Error connecting to IGV?" は別担当)
- **旧 (chip-atlas.org)**: `<a class="infoBtn">&#x24D8;</a>` クリックで `alert()`。ページ全体がブロックされる。
- **新 (localhost:9292)**: `<a class="info-btn" href="#" role="button" aria-label="…">&#x24D8;</a>` に `new Popover(btn, { trigger: 'focus click', placement: 'top', html: false })`。click は `preventDefault`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:118-124, old-app/public/js/pj/peak_browser.js:430-434 / 新: views/enrichment_analysis.erb:49-79, views/diff_analysis.erb:66-76, frontend/components/info-popover.ts:28-48
- **確認方法**: `ソース推定` (`要ブラウザ確認`)
- **備考**: `trigger: 'focus click'` の併用は Bootstrap の想定外の組み合わせ。マウスクリックでは focusin (show を setTimeout 0 で予約) の直後に click (toggle) が走るため、ちらついて閉じる・二度押しが要る、といった挙動になり得る。要ブラウザ確認。安全なのは `trigger: 'focus'` 単独 (次のクリックで閉じる、Bootstrap 公式の dismissible パターン) か `'click'` 単独。

### SHELL-36 コードブロックの copy ボタン: アイコン → テキスト
- **ページ/機能**: `/agents` `/demo` の `<pre>` (`/publications` には新旧とも付かない)
- **旧 (chip-atlas.org)**: `.publication_list pre` に `<i class="far fa-copy">` ボタン、成功時 `fa-check` 1.5 秒。`title="Copy to clipboard"`。
- **新 (localhost:9292)**: `.markdown-content pre` に文字 "Copy"、成功時 "Copied!" 1.5 秒。CSS (位置・色・透明度) は同一値。末尾改行の除去が `/\n$/` → `/\n+$/`。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/_copy_code.haml:19-36, old-app/views/agents.haml:40, demo.haml:40, style.sass:222-238 / 新: views/_copy_code.erb:19-34, views/agents.erb:11, views/demo.erb:11, public/css/style.css:188-207
- **確認方法**: `ソース推定` (`要ブラウザ確認`)

### SHELL-37 ゲノムタブ: 10 アセンブリ → 7 (hg19/mm9/dm3/ce10 削除、TAIR12 追加)
- **ページ/機能**: 全解析ページ上部のゲノムタブ帯
- **旧 (chip-atlas.org)**: `PJ::Experiment.list_of_genome` のハードコード順: H. sapiens (hg38) / H. sapiens (hg19) / M. musculus (mm10) / M. musculus (mm9) / R. norvegicus (rn6) / D. melanogaster (dm6) / D. melanogaster (dm3) / C. elegans (ce11) / C. elegans (ce10) / S. cerevisiae (sacCer3)。本番 `/data/list_of_genome.json` と `/peak_browser` のタブで確認。
- **新 (localhost:9292)**: `config/genomes.yml` 順: hg38 / mm10 / rn6 / dm6 / ce11 / sacCer3 / A. thaliana (TAIR12)。ラベル書式は同一。
- **分類**: `データ差分`
- **影響度**: 高
- **根拠**: 旧: old-app/lib/pj/experiment.rb:56-70, old-app/views/peak_browser.haml:59-65, curl `https://chip-atlas.org/data/list_of_genome.json` / 新: config/genomes.yml:2-16, lib/models/experiment.rb:9-12, curl `/api/genomes`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的 (BRIEF)。hg19/mm9 で解析していた既存ユーザへの告知 (What's new) が新版には無い。Colo ページのみ colo データを持つゲノムに絞る (`Analysis.genomes_with_colo`; TAIR12 は除外) — 詳細は Colo 担当。

### SHELL-38 ゲノムタブの実装: `<a data-toggle=tab>` 事前描画 → JS 生成 `<button role=tab>` + `#genome=` 永続化
- **ページ/機能**: 同上
- **旧 (chip-atlas.org)**: 全ゲノム分のフォームを HTML に事前描画し Bootstrap tab で切替。URL には残らず、リロードで先頭タブに戻る。
- **新 (localhost:9292)**: `GenomeTabs.init` が `<button class="nav-link" role="tab" aria-selected>` を生成し、選択を `location.hash` の `genome=<id>` に `replaceState` で保存・復元。`genome-change` イベントで内容を再描画。JS が動かない環境ではタブ帯が空。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:59-70, old-app/public/js/pj/pj.js:29-47 / 新: frontend/components/genome-tabs.ts:8-17, :32-83
- **確認方法**: `ソース推定` (`要ブラウザ確認`)
- **備考**: `#genome=mm10` 付き URL の共有が可能になった。

### SHELL-39 Enrichment Analysis の「計算サーバ停止中」事前チェックと送信ボタン無効化が無い
- **ページ/機能**: サービス状態表示 > Enrichment Analysis ページ読込時
- **旧 (chip-atlas.org)**: ページ読込時に `fetch("/wabi_endpoint_status")` し、応答が `"chipatlas"` でなければ送信ボタンを `disabled` にして `alert("Enrichment analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.")`。サーバ側は WABI (`https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/`) を 3 秒タイムアウトで GET。
- **新 (localhost:9292)**: `enrichment-analysis.ts` は `/jobs/available` も `/status` も呼ばない。フォームは常に入力可能で、送信失敗時に `submit-status` へ "Submit failed. Try again or check the service status." と出るのみ。`serviceStatus()` (client.ts) はどのページからも呼ばれていない。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:112-125, old-app/app.rb:30-38, :455-457, curl `https://chip-atlas.org/wabi_endpoint_status` → `chipatlas` / 新: frontend/pages/enrichment-analysis.ts (該当コード無し; :789 の失敗文言のみ), frontend/api/client.ts:460-462 (`serviceStatus` 未使用), routes/jobs.rb (`/jobs/available`)
- **確認方法**: `ソース推定`
- **備考**: Diff Analysis 側には同等の仕組みがある (SHELL-40) ので、それを EA にも適用すれば揃う。「check the service status」と案内するが、UI 上にサービス状態を見る場所が無い点も不親切。

### SHELL-40 Diff Analysis の停止通知がインライン化、`/status` エンドポイント新設 (ただし未消費)
- **ページ/機能**: サービス状態表示 > Diff Analysis ページ、`/status`
- **旧 (chip-atlas.org)**: `submitDMR()` が `/wabi_endpoint_status` を見て NG なら `alert("Diff analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.")` + ボタン無効化。全体バナーは無く、ホームの手書き告知 (SHELL-02) で補っていた。
- **新 (localhost:9292)**: `checkJobAvailability('diff_analysis')` (`GET /jobs/available?type=diff_analysis`) の結果で `#unavailable-notice` に "Diff analysis is currently unavailable: no compute backend is serving this job type right now. Please check back later." を表示し送信ボタンを無効化 (チェック失敗時はフェイルオープン)。`/status` (30 秒キャッシュ) は data_server/wabi/wes と 6 機能の状態を返すが、フロントエンドに消費者がおらず、全体バナーも無い。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:116-133 / 新: frontend/pages/diff-analysis.ts:197-260, routes/health.rb:26-40, curl `/status` (`features.diff_analysis: "unavailable"`)
- **確認方法**: `curl+ソース確認済み` (通知の見た目は `要ブラウザ確認`)
- **備考**: 旧の alert より良いが、ホームや他ページからは分からない。`/status` をレイアウト共通のバナーに繋ぐと SHELL-02/39 も同時に解決する。

---

## HTTP レベル

### SHELL-41 HTTP → HTTPS リダイレクト
- **ページ/機能**: `http://chip-atlas.org/`
- **旧 (chip-atlas.org)**: **200** で通常ページを返す (リダイレクト無し)。旧 nginx 設定は `listen 80; server_name _;` のみ。`https://www.chip-atlas.org/` は接続不可 (curl exit 000)。
- **新 (localhost:9292)**: nginx 設定 `config/nginx/chip-atlas.conf:5-9` は `listen 80` で `return 301 https://$host$request_uri`。ローカル docker では nginx 無しのため未検証。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/config/nginx/chip-atlas.conf:5-8, curl `http://chip-atlas.org/` (200, `<title>ChIP-Atlas</title>`) / 新: config/nginx/chip-atlas.conf:5-9
- **確認方法**: `ソース推定` (デプロイ後に要確認)
- **備考**: 本番は現状 HTTP でも配信されているので、HSTS などと併せてセキュリティ担当の項目にもなる。

### SHELL-42 旧パスの消滅 (`/data/*`, `/qvalue_range`, `/wabi_endpoint_status`, `/style.css`, `/js/pj/*.js`, `/api/remoteUrlStatus`)
- **ページ/機能**: 旧 API・旧アセットへの直接アクセス
- **旧 (chip-atlas.org)**: `/data/experiment_types?genome=hg38&clClass=Blood` → 200 JSON、`/wabi_endpoint_status` → `chipatlas`、`/.well-known/mcp.json` → 200、`/api/nonexistent` → HTML 404。
- **新 (localhost:9292)**: 上記は全て **HTML の 404 ページ** (`/api/` 配下のみ JSON `{"error":"Not found"}`)。`/api/remoteUrlStatus` は `/api/remote_url_status` に改名。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:113-192, :227-230, :455-457, :503-505 / 新: routes/pages.rb:152-164, curl 各パス
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的 (BRIEF: `/data/*` → `/api/*`)。詳細は API 担当。旧 llms.txt (SHELL-30) や外部サイトのブックマークからの流入は HTML 404 になる。

### SHELL-43 レスポンスヘッダ・キャッシュ・圧縮・`/health`
- **ページ/機能**: 全応答
- **旧 (chip-atlas.org)**: `x-xss-protection: 1; mode=block`, `x-content-type-options: nosniff`, `x-frame-options: SAMEORIGIN` (Rack::Protection)、`server: nginx/1.18.0`, gzip 有効 (`content-encoding: gzip`)。HTML に Cache-Control 無し。`/style.css` は毎回 sass コンパイル、キャッシュ無し。静的 txt は nginx 直配信 (`content-type: text/plain`, etag)。`/health` → `{"status":"ok","checks":{"database":"ok","config":"ok"}}`。末尾スラッシュ付き URL は 404。
- **新 (localhost:9292)**: 同じ 3 つの保護ヘッダ。`/status` に `cache-control: public, max-age=30`、`/api/stats` 3600、`/api/track_classes` 86400。CSS/JS は `?v=mtime` + nginx `expires 1d`。ローカルは gzip 無し (puma 直); 新 nginx 設定に gzip 指示は無く OS 既定に依存。`/health` → `{"status":"ok","checks":{"database":"ok","experiments":"ok"}}` (`config` → `experiments`)。末尾スラッシュ 404 は同じ。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: curl -D の比較 (`shell/prod/*.headers`, `shell/local/*.headers`), routes/health.rb:8-24, :28, routes/api.rb:54, :62, config/nginx/chip-atlas.conf:26-42
- **確認方法**: `curl+ソース確認済み` (本番 nginx 配下での gzip/expires は `未確認`)

### SHELL-44 `/openapi.yaml` の Content-Type とサイズ
- **ページ/機能**: `/openapi.yaml` (`/agents` `/llms.txt` からリンク)
- **旧 (chip-atlas.org)**: 200, `application/octet-stream` (nginx の mime.types に yaml が無い), 14,790 bytes。
- **新 (localhost:9292)**: 200, `text/yaml;charset=utf-8` (Rack::Static), 46,042 bytes。本番 nginx 経由では旧と同じく octet-stream になる見込み。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: curl 両者 (`-w %{content_type} %{size_download}`)
- **確認方法**: `curl+ソース確認済み`
- **備考**: ブラウザで開くとダウンロードになる。nginx に `types { application/yaml yaml yml; }` を足すと改善。内容差は API 担当。

---

## 要ブラウザ確認リスト

1. SHELL-10: 本番ナビ右側 (ID フォーム/Search) が 2 行に折り返しているか、どの幅で起きるか。新版で 1 行に収まるか (特に 1376〜1600px)。
2. SHELL-11: 768〜991px で新版がハンバーガーになる見た目、折りたたみメニュー内の略称表示。
3. SHELL-14: 本文リンクの常時下線 (/publications で最も目立つ)。
4. SHELL-15/16/17: 見出し・ボタン・入力欄の大きさ、コンテナ幅の差の実感。
5. SHELL-04: What's new ブロックの横位置 (offset 2 → 1)。
6. SHELL-05: 旧ホームのタイルが <992px で横に潰れるか、新版で縦積みになるか。タイルの等高。
7. SHELL-34/35: ⓘ popover の改行消失、`trigger: 'focus click'` でクリック時に確実に開くか (ちらつき・二度押し)、276px 幅での長文の見え方。
8. SHELL-33: Tutorial メニューが右端揃え (`dropdown-menu-end`) で見切れないか。
9. SHELL-28: 本番 404 ページで giphy 画像が実際に出ないこと (mixed content)。
10. SHELL-09: ID ジャンプが新規タブで開くこと (`window.open`)、ポップアップブロッカーの影響 (新旧共通)。
11. SHELL-38: `#genome=` の復元とタブ切替の描画。
12. SHELL-40: Diff Analysis の停止通知の見た目、ボタン無効化。
13. SHELL-36: copy ボタンのクリップボード動作 (HTTPS 必須の `navigator.clipboard`)。

## 未確認・不確実事項

- 本番の `updates.markdown` 以外にも、サーバ上で直接編集されたファイルがある可能性 (JS は同一と BRIEF で確認済み、publications/agents/demo の markdown はレンダリング結果からリポジトリと一致と判断)。HAML/style.sass の本番実体は未検証 (レンダリング結果からは一致)。
- 旧の "ID:" ラベル色は BS3.2.0 の `.navbar-inverse .navbar-text{color:#777}` と判断したが、style.sass の `.navbar.navbar-inverse a` は `<a>` にしか効かないため `<span>` は灰色のまま、という推定。
- 新版本番の nginx が `config/nginx/chip-atlas.conf` どおりに配置されるか (HTTPS リダイレクト、expires、gzip、openapi の mime) は未検証。
- kramdown の `gfm_autolink` オプション (SHELL-20 の修正案 b) が Gemfile.lock の kramdown-parser-gfm バージョンで使えるかは未確認。
- 「over 1M experiments」(llms.txt / demo) の根拠は新旧とも不明 (実数 45 万)。
- `/view?id=GSM1` の旧挙動 (302 → `/view?id=`) は 1 回の GET で確認したが、`gsm_to_srx` が nil を返す全ケースで同じかは未検証。
- 本番のナビが 2 行になる (72px) という記述は新版 CSS コメントと docs/ui-parity-audit-2026-09-14.md に依拠しており、本レポートでは実測していない。
- `/status` の `wes: "not_checked"` の意味と、`features.diff_analysis` が本番相当環境でどうなるかは Jobs/API 担当の範囲。
- 新版で `/agents` `/demo` にアクティブ状態が無いのは項目削除の帰結であり、`@active_menu` の設定が残っているのは無害だが未整理。
