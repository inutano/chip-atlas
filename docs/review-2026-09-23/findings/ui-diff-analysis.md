# Diff Analysis (DA) 新旧比較レポート — 2026-09-23

## 担当範囲の要約

- 対象: Diff Analysis の設定ページ (`/diff_analysis`)、投入処理、Estimated run time、結果ページ (`/diff_analysis_result`)、実行ログ表示。旧: `old-app/views/diff_analysis(_result).haml`, `old-app/public/js/pj/diff_analysis(_result).js`, `old-app/app.rb`。新: `views/diff_analysis(_result).erb`, `frontend/pages/diff-analysis.ts`, `diff-result.ts`, `frontend/components/{job-tracker,genome-tabs,info-popover,result-page-params}.ts`, `routes/jobs.rb`, `lib/services/{compute_router,wabi_service}.rb`。
- 本番配信 JS と `old-app/public/js/pj/diff_analysis(_result).js` は md5 一致 (17309398…, be83044c…) を再確認。`diff-analysis.examples.json` は本番・old-app・新版の 3 者で md5 一致 (52792a7f…)。新版のビルド済 `public/js/diff-analysis.js` / `diff-result.js` は TS ソースの文言を含み、localhost 配信物と md5 一致。
- **最重要**: 新版では `ComputeRouter::JOB_TYPE_BACKENDS['diff_analysis'] = []` のため、WABI が生きていても Diff Analysis の投入は常に不可 (`/jobs/available?type=diff_analysis` → `{"backend":null,"available":false}`、`/status` → `diff_analysis: "unavailable"`)。本番は現時点で `/wabi_endpoint_status` = `chipatlas` で投入可能。コードコメントは「WABI は現在 Diff Analysis を受け付けない」と主張するが、投入禁止のため真偽は未検証。
- Estimated run time の式は新旧で同一だが、本番 DB は 1 SRX につきアセンブリごとに 1 行 (hg38+hg19 等) を持ち、旧実装はそれを二重加算する。人・マウス (・おそらくハエ・線虫) では表示分数が異なる (人の diffbind 例: 本番 30 mins / 新 21 mins)。
- 結果ページ: 新版は URL に `backend=` を必須化したため、本番形式の結果 URL (`?id=…&title=…&genome=…&calcm=…`) を開くと「Missing id or backend parameter in URL.」となる (要修正)。また WABI 停止時、旧は Status 欄に「server unavailable」を表示するが、新は 503 を例外として握りつぶし「Requesting」のまま無反応 (要修正)。
- 改良点: alert() 廃止 (インライン通知/ポップオーバー)、入力検証追加、Estimated の debounce と「null mins」「Invalid Date」系バグの解消、Submitted at を WABI リクエスト ID から復元、ログの textContent 描画と終了後のポーリング停止、Status の正直な表示 (unknown)。
- 文言差: 見出し 3 箇所、ラジオ表記、placeholder、ボタン大文字化、リード文の句点、テーブル見出しのコロン除去、脚注の句点、ヘルプ文が新見出しと不一致 (要修正・低)。
- 件数: 改良 14 / 単なる変更 13 / 機能削除 2 / 退行 (要修正) 3 / データ差分 2 / 新機能 1 (計 35 項目)。

---

## 設定ページ (`/diff_analysis`)

### DA-01 新版では Diff Analysis の投入が常に不可 (バックエンド未割当)
- **ページ/機能**: Diff Analysis > 4. Analysis description > Submit ボタン / 利用可否
- **旧 (chip-atlas.org)**: ページ読込時に `GET /wabi_endpoint_status` を呼び、応答が `chipatlas` なら Submit 有効。現在の本番応答は `chipatlas` (curl 確認) で、投入可能な状態。
- **新 (localhost:9292)**: ページ読込時に `GET /jobs/available?type=diff_analysis` を呼ぶが、`ComputeRouter::JOB_TYPE_BACKENDS` で `diff_analysis` に割り当てられたバックエンドが空のため、WABI の生死に関係なく常に `{"backend":null,"available":false}`。結果、パネル 4 に黄色い警告「Diff analysis is currently unavailable: no compute backend is serving this job type right now. Please check back later.」が常時表示され、Submit は disabled。`/status` も `"diff_analysis":"unavailable"` を返す。仮に Submit できても `POST /jobs/submit` は同じ判定で 503 を返す (ソース推定、投入禁止のため未実行)。
- **分類**: `機能削除`
- **影響度**: 高
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:116-134, old-app/app.rb:455-457, 477-479, `curl https://chip-atlas.org/wabi_endpoint_status` → `chipatlas` / 新: lib/services/compute_router.rb:21-24, 29-39, 50-52, routes/jobs.rb:45-48, 51-61, routes/health.rb:36-37, frontend/pages/diff-analysis.ts:204-205, 238-258, `curl localhost:9292/jobs/available?type=diff_analysis` → `{"backend":null,"available":false}`, `curl localhost:9292/status` → `features.diff_analysis: "unavailable"`
- **確認方法**: `curl+ソース確認済み`
- **備考**: compute_router.rb:13-20 のコメントは「WABI は現在 Diff Analysis を提供していない (以前は到達可能なら常に ok と誤報告していた)」と述べるが、本番は同じ WABI エンドポイントに `antigenClass=diffbind|dmr` で投入している。本番の Diff Analysis ジョブが実際に完走するかは投入禁止のため未検証。**オーナー判断が必要**: WABI が本当に受け付けないなら本番も同様に壊れており、受け付けるなら `JOB_TYPE_BACKENDS['diff_analysis'] = %w[wabi]` で復活する (1 行)。デプロイ前に必ず決着させること。

### DA-02 「利用不可」時の表示方法 (alert → インライン警告)
- **ページ/機能**: Diff Analysis > Submit ボタン付近
- **旧 (chip-atlas.org)**: `wabi_endpoint_status` が `chipatlas` 以外 (WABI 停止・タイムアウト・fetch 失敗を含む) のとき、ブロッキング `alert("Diff analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.")` (原文ママ、"maintainance" は誤綴) を出し、ボタンを disabled。ページ上に恒久的な表示は残らない。
- **新 (localhost:9292)**: `#unavailable-notice` (Bootstrap `alert alert-warning small`) にメッセージを常時表示し Submit を disabled。可否チェック自体が失敗 (ネットワークエラー等) した場合は **フェイルオープン** でフォームを有効のまま (POST 側で再判定するため)。サイト全体のステータスバナーは無い (`serviceStatus()` は client.ts で定義のみ、呼出し箇所なし)。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:128-133 / 新: views/diff_analysis.erb:79, frontend/pages/diff-analysis.ts:215-243, 245-258
- **確認方法**: `curl+ソース確認済み` (見た目は要ブラウザ確認)
- **備考**: 表示自体は改良だが、DA-01 により現状「常に」この警告が出る。

### DA-03 リード文に句点が追加 (両ページ)
- **ページ/機能**: Diff Analysis / Diff Analysis Result > ページヘッダ
- **旧 (chip-atlas.org)**: 「Detect differential peaks or differentially methylated regions」(句点なし)
- **新 (localhost:9292)**: 「Detect differential peaks or differentially methylated regions.」(句点あり)。h1「ChIP-Atlas: Diff Analysis」と `<title>` は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:34-35, diff_analysis_result.haml:32-33 / 新: views/diff_analysis.erb:10, views/diff_analysis_result.erb:9, curl 可視テキスト
- **確認方法**: `curl+ソース確認済み`

### DA-04 Tutorial ドロップダウンの実装差 (div → button)
- **ページ/機能**: Diff Analysis > ヘッダ右「Tutorial」
- **旧 (chip-atlas.org)**: `div.button.btn.btn-primary.dropdown-toggle` (button 要素ではない div に `type="button"`) + `span.caret`。項目は「PDF」1 件 (`https://chip-atlas.dbcls.jp/data/manual/Diff_Analysis/Diff_Analysis.pdf`, target=_blank)。
- **新 (localhost:9292)**: 実 `<button>` + Bootstrap 5 `dropdown-menu-end`。項目「PDF」同一 URL、`rel="noopener noreferrer"` 付き。Movie/統合TV 項目は旧同様なし。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:37-45 / 新: views/diff_analysis.erb:11-13, views/_tutorial.erb:7-25, views/_page_header.erb:13-30
- **確認方法**: `curl+ソース確認済み` (配置は要ブラウザ確認)

### DA-05 ゲノムタブ 10 → 7 (hg19/mm9/dm3/ce10 削除、TAIR12 追加)
- **ページ/機能**: Diff Analysis > ゲノムタブ
- **旧 (chip-atlas.org)**: `H. sapiens (hg38)`, `H. sapiens (hg19)`, `M. musculus (mm10)`, `M. musculus (mm9)`, `R. norvegicus (rn6)`, `D. melanogaster (dm6)`, `D. melanogaster (dm3)`, `C. elegans (ce11)`, `C. elegans (ce10)`, `S. cerevisiae (sacCer3)` の 10 タブ (サーバ側描画、タブごとに独立した DOM)。
- **新 (localhost:9292)**: `hg38, mm10, rn6, dm6, ce11, sacCer3, TAIR12 (A. thaliana)` の 7 タブ (JS 描画、共有 DOM)。
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 旧: old-app/views/diff_analysis.haml:51-55, old-app/lib/pj/experiment.rb:56-70, `curl https://chip-atlas.org/data/list_of_genome.json` / 新: views/diff_analysis.erb:6,17, routes/pages.rb:106-110, `curl localhost:9292/api/genomes`
- **確認方法**: `curl+ソース確認済み`
- **備考**: BRIEF の「意図的変更」と一致。TAIR12 の Diff Analysis を WABI が扱えるかは不明 (DA-13 も参照)。

### DA-06 選択ゲノムを URL ハッシュ `#genome=` に保持
- **ページ/機能**: Diff Analysis > ゲノムタブ
- **旧 (chip-atlas.org)**: タブ状態は URL に残らない (`href="#hg38-tab-content"` の Bootstrap 3 タブ)。
- **新 (localhost:9292)**: タブ切替で `history.replaceState` により `#genome=mm10` を書き込み、再読込・共有時に復元。タブは `<button role="tab" aria-selected>`。旧形式ハッシュ (`#hg19-tab-content`) や削除ゲノム (`#genome=hg19`) は無視され先頭タブに戻る。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 新: frontend/components/genome-tabs.ts:8-17, 26-30, 51-60, 79-82
- **確認方法**: `ソース推定` (要ブラウザ確認)

### DA-07 パネル 1 の見出しとラジオ表記
- **ページ/機能**: Diff Analysis > 1. パネル
- **旧 (chip-atlas.org)**: 見出し「1. Choose experiment type」、ラジオ「ChIP/ATAC/DNase-seq」(既定・値 `diffbind`) / 「Bisulfite-seq」(値 `dmr`)。ゲノムごとに別 name (`hg38DiffOrDMR` 等) の独立ラジオ。
- **新 (localhost:9292)**: 見出し「1. Experiment type」、ラジオ「ChIP / ATAC / DNase-seq」(スペース入り、既定) / 「Bisulfite-seq」。全ゲノム共通の 1 組 (`name="analysis-type"`)。選択値がそのまま WABI の `antigenClass` (diffbind/dmr) と閾値 (50/999) を決める点は新旧同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:66-77, old-app/public/js/pj/diff_analysis.js:138-141, 156-160 / 新: views/diff_analysis.erb:22-31, frontend/pages/diff-analysis.ts:99-102, 185-195, lib/services/wabi_service.rb:45-48
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧はゲノムごとにラジオ状態が独立 (hg38 で DMR にしても mm10 は diffbind のまま)。新は全ゲノム共通なので、タブを切り替えてもラジオ選択が引き継がれる (挙動差、要ブラウザ確認)。

### DA-08 パネル 2/3 の見出し「Enter dataset A/B」→「Dataset A/B (Experiment IDs)」
- **ページ/機能**: Diff Analysis > 2./3. パネル
- **旧 (chip-atlas.org)**: 見出し「2. Enter dataset A」「3. Enter dataset B」、その下に小見出し行「Experiment IDs」、次に textarea。
- **新 (localhost:9292)**: 見出し「2. Dataset A (Experiment IDs)」「3. Dataset B (Experiment IDs)」、小見出し行なし。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:81-90, 99-108 / 新: views/diff_analysis.erb:38, 50
- **確認方法**: `curl+ソース確認済み`
- **備考**: docs/ui-parity-audit-2026-09-14.md:228 でも未対応の文言差として記録済み。DA-15 (ヘルプ文の不一致) の原因。

### DA-09 textarea の placeholder
- **ページ/機能**: Diff Analysis > 2./3. パネル textarea
- **旧 (chip-atlas.org)**: 「SRX or GSM ID(s)」(rows=8)
- **新 (localhost:9292)**: 「SRX or GSM ID(s), one per line」(rows=8)
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:90, 108 / 新: views/diff_analysis.erb:40, 52
- **確認方法**: `curl+ソース確認済み`

### DA-10 ID 入力の解釈 (生テキスト送信 → 正規化)
- **ページ/機能**: Diff Analysis > 2./3. パネル > 入力方式
- **旧 (chip-atlas.org)**: 入力は新旧とも textarea への貼り付けのみ (typeahead・リスト選択・ファイル添付は旧にも無い)。旧は textarea の内容をそのまま `bedAFile`/`bedBFile` として WABI に送る (空行・前後空白・カンマ区切りもそのまま)。Estimated 用の分割は改行のみ (`split(/\r?\n/)`)。
- **新 (localhost:9292)**: 空白・改行・カンマで分割し、空要素を除いて `"\n"` で再結合してから送信。Estimated も同じ分割。したがって「SRX1, SRX2」を 1 行に書いても 2 ID として扱われる。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:145, 149, 232-241 / 新: frontend/pages/diff-analysis.ts:104-106, 125-128, 189, 191, 349-350
- **確認方法**: `ソース推定`

### DA-11 ゲノム別のデータセット保持と、実験タイプ切替時のクリア
- **ページ/機能**: Diff Analysis > 2./3. パネル > タブ切替・ラジオ切替
- **旧 (chip-atlas.org)**: ゲノムごとに textarea が別 DOM のため、タブを切り替えても各ゲノムの入力は保持される。ラジオ (diffbind↔dmr) を変えると、表示中ゲノムの A/B textarea を空にし Estimated を「-」に戻す (他ゲノムは影響なし)。
- **新 (localhost:9292)**: 共有 textarea だが `genome-change` 時にゲノム別ストアへ退避・復元するので、ユーザから見た保持挙動は同じ。ラジオ変更時は表示中ゲノムの textarea とストアを空にし Estimated を「—」に戻す。切替前に確認ダイアログは新旧とも無し。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:37-49 / 新: frontend/pages/diff-analysis.ts:59-85, 272-289, 310-317, frontend/pages/diff-analysis.test.ts:78-107
- **確認方法**: `ソース推定` (要ブラウザ確認)
- **備考**: 可視挙動は同一。ただし新はラジオが全ゲノム共通 (DA-07 備考) なので、「hg38 で DMR に切替 → mm10 タブへ」とすると mm10 も DMR 表示になるが mm10 の textarea はクリアされない点が旧と異なる (旧は mm10 のラジオが独立)。

### DA-12 タイトル欄の既定値がタブクリックのたびに上書きされる (旧) → 一度だけ (新)
- **ページ/機能**: Diff Analysis > 4. Analysis description > Analysis title / Dataset A title / Dataset B title
- **旧 (chip-atlas.org)**: 読込時に先頭ゲノムの 3 欄へ「My project」「dataset A」「dataset B」を投入。タブクリックのたびに `putDefaultTitles()` が呼ばれ、表示先ゲノムの 3 欄を既定値で上書きする (ゲノムごとに別入力欄)。ユーザが hg38 のタイトルを編集 → mm10 → hg38 と戻ると編集内容が既定値に戻る (ソース推定)。
- **新 (localhost:9292)**: 読込時に同じ 3 値を一度だけ投入し、以後タブ切替では触らない。3 欄は全ゲノム共通。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:23-34, 211-221 / 新: frontend/pages/diff-analysis.ts:49-51, 266-270
- **確認方法**: `ソース推定` (旧の上書きは Bootstrap 3 の `li.active` 同期更新に依存。要ブラウザ確認)

### DA-13 「Try with example」の有無・内容・例外時の表示
- **ページ/機能**: Diff Analysis > 2./3. パネル > Try with example
- **旧 (chip-atlas.org)**: 両パネルに存在。`/diff-analysis.examples.json` を読み、種 (ゲノム名の末尾数字を除去: hg38→hg, sacCer3→sacCer) × 実験タイプ × dataSetA/B の ID を改行区切りで投入し Estimated を更新。**ce11/ce10 + Bisulfite-seq** ではラジオ切替時点でリンクが「no public data available」のテキストに置換され、placeholder も空になる (戻すと復元)。JSON 取得失敗時は無反応。
- **新 (localhost:9292)**: 両パネルに存在。JSON は旧・本番と byte 一致 (md5 52792a7f…)、種キーの導出も同一 (`genomeSpecies`)。例が空のとき (ce + dmr) は **クリック後に** Submit 下の `#submit-status` に「No example data available for this genome and experiment type.」を表示。**TAIR12** は JSON に `TAIR` キーが無いため両タイプとも常に同メッセージ。JSON 取得失敗時は「Failed to load example data.」。
- **分類**: `単なる変更` (TAIR12 の例が無い点は `データ差分`)
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:16-20, 51-91, 94-113, old-app/public/diff-analysis.examples.json:49-57 / 新: frontend/pages/diff-analysis.ts:110-122, 319-344, public/diff-analysis.examples.json (diff → IDENTICAL), `curl localhost:9292/diff-analysis.examples.json` → 200
- **確認方法**: `curl+ソース確認済み` (表示は要ブラウザ確認)
- **備考**: 例の SRX が新ローカル DB に存在することは `/api/experiment` で確認 (SRX4099758 等)。TAIR12 用の例を JSON に追加するか、リンク自体を隠すかを検討。

### DA-14 ⓘ ボタン: alert() → Bootstrap ポップオーバー
- **ページ/機能**: Diff Analysis > 4. Analysis description > 3 つの ⓘ
- **旧 (chip-atlas.org)**: 3 つとも `a.infoBtn` (href 無し、キーボード到達不可)。クリックで `alert()`。文言は「Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).」等 (改行 1 つ含む)。
- **新 (localhost:9292)**: 3 つとも `a.info-btn[href="#"][role=button][aria-label]`。focus/click で上方向ポップオーバー (`html:false`)。文言は旧と文字列一致 (HELP_TEXT)。ただし `html:false` のため文中の `\n` は改行として描画されない可能性 (要ブラウザ確認)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:125-138, old-app/public/js/pj/diff_analysis.js:265-289 / 新: views/diff_analysis.erb:66, 71, 76, frontend/pages/diff-analysis.ts:22-29, 292, frontend/components/info-popover.ts:28-48
- **確認方法**: `curl+ソース確認済み` (描画は要ブラウザ確認)

### DA-15 ヘルプ文が新見出しと不一致 (「2. Enter dataset A」を参照)
- **ページ/機能**: Diff Analysis > Dataset A title / Dataset B title の ⓘ
- **旧 (chip-atlas.org)**: 「Enter a title for the data selected in "2. Enter dataset A".」— 見出し「2. Enter dataset A」と一致。
- **新 (localhost:9292)**: 同じ文言を流用しているが、新見出しは「2. Dataset A (Experiment IDs)」(DA-08) なので、存在しない見出しを参照している。
- **分類**: `退行 (要修正)`
- **影響度**: 低
- **根拠**: 新: frontend/pages/diff-analysis.ts:25-28 vs views/diff_analysis.erb:38, 50
- **確認方法**: `ソース推定`
- **備考**: 見出しを旧に戻す (DA-08) か HELP_TEXT を書き換えるか、どちらかで解消。

### DA-16 タイトル入力欄の見た目 (form-inline → label + form-control-sm)
- **ページ/機能**: Diff Analysis > 4. Analysis description
- **旧 (chip-atlas.org)**: `p.form-control-static` のラベル + 通常サイズ `input.form-control` (label 要素なし)。
- **新 (localhost:9292)**: `<label for=…>` (small text-muted) + `input.form-control-sm`。既定値 (My project / dataset A / dataset B) は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:122-139 / 新: views/diff_analysis.erb:64-78
- **確認方法**: `curl+ソース確認済み` (見た目は要ブラウザ確認)

### DA-17 Submit ボタンの表記「submit」→「Submit」
- **ページ/機能**: Diff Analysis > Submit ボタン
- **旧 (chip-atlas.org)**: 「submit」(小文字、`btn-lg btn-block`)
- **新 (localhost:9292)**: 「Submit」(`btn-lg` + `d-grid` で全幅)
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis.haml:141-143 / 新: views/diff_analysis.erb:80-82
- **確認方法**: `curl+ソース確認済み`

### DA-18 Estimated run time の更新タイミングと空入力時の表示
- **ページ/機能**: Diff Analysis > Estimated run time
- **旧 (chip-atlas.org)**: 初期表示「-」。textarea の `click / keyup / paste` ごとに即 `POST /diff_analysis_estimated_time` (1 キーごとに 1 リクエスト)。`paste` は値反映前に発火するため貼付直後は貼付前の値で計算される。**空の textarea をクリックしただけでも** ids=[] で POST され、diffbind では 0 reads → (119.38+600)/60 ≈ 12 → 「12 mins」と表示される。値は `<a>` 要素 (href なし)。
- **新 (localhost:9292)**: 初期表示「—」。`input` イベントを 500 ms デバウンスして POST。ID が 0 件なら POST せず「—」。例の投入・ゲノム切替・ラジオ切替時にも再計算。失敗時は「(failed)」。値は `<span>`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:224-263, old-app/views/diff_analysis.haml:144-147 / 新: frontend/pages/diff-analysis.ts:124-144, 288, 294-300, 315, views/diff_analysis.erb:83-85; `curl -X POST localhost:9292/jobs/estimated_time -d '{"analysis":"diffbind","ids":[]}'` → `{"minutes":12}`
- **確認方法**: `curl+ソース確認済み`

### DA-19 Estimated run time の数値差: 本番はアセンブリ重複行を二重加算
- **ページ/機能**: Diff Analysis > Estimated run time (表示分数)
- **旧 (chip-atlas.org)**: 式は DMR `117.13·ln(X) − 2012.5 + 600` 秒、diffbind `1.80e-6·X + 119.38 + 600` 秒、`round(秒/60)`。X は `Experiment.where(expid: ids)` の `readInfo` 先頭値の合計。本番 DB は 1 SRX につきアセンブリごとに 1 行あるため (`/data/exp_metadata.json?expid=SRX4099758` → hg38 行と hg19 行、reads 同値 43,876,998)、人 (hg38+hg19)・マウス (mm10+mm9) では X が 2 倍になる。人 diffbind 例 (SRX4099758/59, SRX3481056/57) の本番 reads 合計は 2×295,925,622 → **30 mins** (本番への POST は禁止のため、本番の reads 値から式で算出)。
- **新 (localhost:9292)**: 式・丸めは同一 (routes/jobs.rb:127-133)。X は SQL `SUM(CAST(SUBSTR(read_info,1,INSTR(read_info,',')-1)))`。新 DB は 1 SRX 1 行なので同じ例で **21 mins** (curl 実測)。rn6/sacCer3 (本番でも 1 行) は一致 (rn 例: 23 mins、SRX10580924 の reads 値も一致)。dm/ce は dm6+dm3 / ce11+ce10 で同様に差が出る見込み (未実測)。
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:392-414, old-app/lib/pj/experiment.rb:250-252 / 新: routes/jobs.rb:125-134, lib/models/experiment.rb:201-207; `curl localhost:9292/jobs/estimated_time` (hg 例 → 21, rn 例 → 23), `curl https://chip-atlas.org/data/exp_metadata.json?expid=SRX4099758`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新の方が「reads を 1 回だけ数える」という意味では正しい。ただし回帰式 (app.rb コメント「from Zou-san」) が本番の二重加算された X に対して当てはめられていた場合、新版の推定は人・マウス等で計算部分が約半分に過小になる。式の由来をオーナーに確認要。

### DA-20 Estimated が算出不能のときの表示 (「null mins」→「—」)
- **ページ/機能**: Diff Analysis > Estimated run time
- **旧 (chip-atlas.org)**: Bisulfite-seq で ID が DB に無い/空のとき (X=0 → ln(0)=−∞ → `minutes: null`)、JS が `null + " mins"` を表示 → 「null mins」。この文字列が結果ページの `calcm` に渡り DA-28 の表示崩れを起こす。POST 失敗時は `alert("Something went wrong: …")`。
- **新 (localhost:9292)**: `minutes` が null なら「—」。POST 失敗時は「(failed)」(alert なし)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:250-261 / 新: frontend/pages/diff-analysis.ts:139-143; `curl -X POST localhost:9292/jobs/estimated_time -d '{"analysis":"dmr","ids":["SRX0000000"]}'` → `{"minutes":null}`; node で `null + " mins"` → `"null mins"` を確認
- **確認方法**: `curl+ソース確認済み`

### DA-21 入力検証 (無し → 各データセット 1 ID 以上)
- **ページ/機能**: Diff Analysis > Submit 時の検証
- **旧 (chip-atlas.org)**: 検証なし。両 textarea が空でも WABI にそのまま投入される。
- **新 (localhost:9292)**: A/B いずれかが 0 件なら「Both datasets must contain at least one experiment ID.」を `#submit-status` に表示して中止。ゲノム未選択時「Select a genome tab first.」(実際には初期タブが必ず選ばれるため到達しない)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:122-127, 136-163 / 新: frontend/pages/diff-analysis.ts:348-358
- **確認方法**: `ソース推定`
- **備考**: 新旧とも未実装の検証: 各群の最小反復数 (例: diffbind の 2 反復)、上限件数、A/B 間の重複 ID、ID 書式 (SRX/GSM/ERX/DRX)、ID のゲノム整合、タイトルの許容文字 (ヘルプ文に書かれているが未検証)。

### DA-22 二重投入防止の不在 (新旧共通)
- **ページ/機能**: Diff Analysis > Submit ボタンの disabled 制御
- **旧 (chip-atlas.org)**: クリック時に disabled → 直後に再有効化 (実質無効化なし)。`complete`/`catch` で未定義変数 `button` を参照 (ReferenceError、ただし success でリダイレクト済み)。
- **新 (localhost:9292)**: 「Submitting…」を表示するがボタンは disabled にしない。応答待ちの間に再クリックすると再投入される。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:122-127, 200-207 / 新: frontend/pages/diff-analysis.ts:370-384
- **確認方法**: `ソース推定`
- **備考**: 新版で `await submitJob` の前後に `disabled` を切り替える 2 行で解消できる。

### DA-23 投入失敗時のフィードバック (alert → インライン文言)
- **ページ/機能**: Diff Analysis > Submit 失敗時
- **旧 (chip-atlas.org)**: `alert("Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." + JSON.stringify(response))` (jqXHR の JSON が付く)。WABI が停止していれば `POST /wabi_chipatlas` が 503。
- **新 (localhost:9292)**: `#submit-status` に「Submit failed. Try again or check the service status.」。サーバは 503 (`No compute backend available`) / 502 (`Compute backend rejected the submission`) / 500 を区別するが、画面には区別が出ない。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:192-199, old-app/app.rb:478-479 / 新: frontend/pages/diff-analysis.ts:380-383, routes/jobs.rb:56-74
- **確認方法**: `ソース推定`

### DA-24 投入ペイロード: WABI へ渡るキー・定数は同一、経路のみ変更
- **ページ/機能**: Diff Analysis > 投入 (ユーザ可視の帰結)
- **旧 (chip-atlas.org)**: ブラウザが 16 キー (`address:""`, `antigenClass`, `title`, `genome`, `typeA:"srx"`, `bedAFile`, `descriptionA`, `typeB:"srx"`, `bedBFile`, `descriptionB`, `format:"text"`, `result:"www"`, `cellClass:"empty"`, `permTime:1`, `sbatchOptions:"-p epyc -t 180"`, `threshold` 50|999) を JSON で `POST /wabi_chipatlas` → サーバが form-encode して WABI へ。
- **新 (localhost:9292)**: ブラウザは 7 キー (`genome, antigenClass, bedAFile, descriptionA, bedBFile, descriptionB, title`) を `POST /jobs/submit {type:"diff_analysis", params}` → `WabiService` が残り 9 キーを同じ値でマージ。データセット名 (`descriptionA/B`) は旧と同じくタイトル欄の値。`antigenClass` が不明値なら例外で拒否。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:136-163, old-app/app.rb:477-501 / 新: frontend/pages/diff-analysis.ts:185-195, lib/services/wabi_service.rb:19-48, 151-162, frontend/pages/diff-analysis.test.ts:28-68
- **確認方法**: `ソース推定` (投入禁止のため実送信は未確認)
- **備考**: 可視の帰結は DA-10 の ID 正規化のみ。

### DA-25 旧エンドポイントの廃止 (`/wabi_endpoint_status`, `/wabi_chipatlas`, `/diff_analysis_log`, `/diff_analysis_estimated_time`)
- **ページ/機能**: Diff Analysis > 内部 API (直接アクセス・スクリプト利用)
- **旧 (chip-atlas.org)**: 上記 4 経路が存在 (`GET /diff_analysis_log?id=` は誰でも WABI ログを取得可)。
- **新 (localhost:9292)**: いずれも 404。代替は `/jobs/available`, `/jobs/submit`, `/jobs/:id/log?backend=`, `/jobs/estimated_time`。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: old-app/app.rb:374-381, 392-414, 455-501 / 新: curl で 4 経路とも 404、routes/jobs.rb 全体
- **確認方法**: `curl+ソース確認済み`
- **備考**: SHIKINEN-SENGU.md:905-906 は `/diff_analysis_log` と `/diff_analysis_estimated_time` を「Keep」としているが実装は廃止。UI 上は影響なし (新 UI は新経路のみ使用)。

---

## 結果ページ (`/diff_analysis_result`)

### DA-26 結果 URL の形式変更と `backend=` 必須化 (旧形式 URL が開けない)
- **ページ/機能**: Diff Analysis Result > URL パラメータ
- **旧 (chip-atlas.org)**: 投入後 `/diff_analysis_result?id=<requestId>&title=<タイトル生値>&genome=<genome>&calcm=<推定文字列からハイフン除去>` へ遷移。`title`/`calcm` は URL エンコードされないため `&` `#` `=` を含むタイトルは壊れる。`genome` は IGV 用の未使用コードにしか使われない。
- **新 (localhost:9292)**: `/diff_analysis_result?id=<job_id>&backend=wabi&title=<enc>&calcm=<enc>` (encodeURIComponent 済、`URLSearchParams` で読取)。**`id` と `backend` のどちらかが無いと**「Missing id or backend parameter in URL.」を赤い alert で表示し、テーブルを隠す。本番形式 (backend なし) の URL は開けない。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/diff_analysis.js:181-190, old-app/public/js/pj/diff_analysis_result.js:21-51 / 新: frontend/pages/diff-analysis.ts:375-379, frontend/components/result-page-params.ts:32-43, frontend/pages/diff-result.ts:11-20, views/diff_analysis_result.erb:14
- **確認方法**: `ソース推定` (エラー表示は要ブラウザ確認)
- **備考**: 結果 URL は「1 週間有効」と案内しており、切替直後にユーザが手元に持つ旧形式 URL が全て無効になる。`backend` 欠落時は `wabi` を既定にする (1 行) ことを推奨。

### DA-27 「Submitted at」の算出 (ページ表示時刻 → WABI リクエスト ID から復元)
- **ページ/機能**: Diff Analysis Result > Submitted at
- **旧 (chip-atlas.org)**: `new Date()` (ページを開いた時刻)。後日 URL を開き直すと「開き直した時刻」が Submitted at として表示される。
- **新 (localhost:9292)**: `wabi_chipatlas_YYYY-MMDD-HHMM-SS-…` 形式の ID から JST として復元、形式外なら旧同様に現在時刻。表示形式「HH:MM:SS (Mon-DD-YYYY) / UTC: HH:MM:SS (Mon-DD-YYYY)」は新旧同一 (node で旧関数を再現し確認)。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/diff_analysis_result.js:54-73 / 新: frontend/components/job-tracker.ts:54-61, 80-86, 297-298, frontend/components/job-tracker.test.ts:34-56
- **確認方法**: `ソース推定` (ID 形式はテストに記載の実ジョブ 2 件に基づく。要実ジョブ確認)

### DA-28 「Estimated finishing time」の表示崩れ解消
- **ページ/機能**: Diff Analysis Result > Estimated finishing time
- **旧 (chip-atlas.org)**: 推定が「-」のまま投入すると `calcm` は空文字になり (ハイフン除去のため `"-" == calcm` 分岐に入らない)、`parseInt(undefined)` = NaN → 「undefined (Date-undefined-undefined) / UTC: undefined (undefined-Date-undefined)」と表示 (node で旧コードを実行し確認)。「null mins」(DA-20) でも同じ。推定があれば 現在時刻 + 分。
- **新 (localhost:9292)**: `calcm` が「N mins」「N.N hr」以外なら「—」。あれば Submitted at + 分。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis_result.js:75-98, diff_analysis.js:178-180 / 新: frontend/components/job-tracker.ts:104-118, 300-301
- **確認方法**: `ソース推定` (旧の文字列は node で再現)

### DA-29 ジョブ情報テーブルの見出し・脚注・配置
- **ページ/機能**: Diff Analysis Result > job-info テーブル
- **旧 (chip-atlas.org)**: 行見出しは td で「Project title」「Request ID」「Submitted at:」「Estimated finishing time:」「Current time:」「Status」「Download Result:」(コロン混在)。脚注「… Please check computation node status here (epyc.q)」。`.container.job-info` 入れ子。
- **新 (localhost:9292)**: `th scope="row"` (太字・幅 30%) で「Submitted at」「Estimated finishing time」「Current time」「Download Result」(コロンなし)。脚注は同文だが末尾「(epyc.q).」と句点付き、`text-muted small`。`col-md-10 offset-md-1` で中央寄せ。冒頭文「Result page URL will be available for a week from the time when 'status' is 'finished'.」は同一。Status 初期値「Requesting」も同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis_result.haml:34-75 / 新: views/diff_analysis_result.erb:12-50, public/css/style.css:672-688
- **確認方法**: `curl+ソース確認済み` (見た目は要ブラウザ確認)

### DA-30 Status ポーリングの方式・語彙・色
- **ページ/機能**: Diff Analysis Result > Status
- **旧 (chip-atlas.org)**: 10 秒後から 10 秒間隔で `GET /wabi_chipatlas?id=` を呼ぶ。サーバは WABI の `?info=result&format=html` を GET し 200 なら「finished」、それ以外 (実行中・待機中・**存在しない/期限切れ ID** も) は「running」、ping 失敗で「server unavailable」。「finished」で赤字表示・停止。
- **新 (localhost:9292)**: 即時 + 10 秒間隔で `GET /jobs/:id/status?backend=wabi`。サーバは WABI `?info=status` の `status:` 行をそのまま返し、取得不能・未知 ID は「unknown」(curl: `test123` → `"status":"unknown"`)。`finished/completed/success` は緑太字で停止、`error/failed` は赤太字で停止、それ以外の語 (running 等、「unknown」を含む) は生表示のまま継続ポーリング。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:460-474, old-app/public/js/pj/diff_analysis_result.js:107-125 / 新: routes/jobs.rb:78-91, lib/services/wabi_service.rb:106-137, frontend/components/job-tracker.ts:16-20, 173-184, 201-225
- **確認方法**: `curl+ソース確認済み` (実ジョブでの語彙は要実ジョブ確認)
- **備考**: 「finished」の色が赤→緑に変わる (単なる変更)。WABI が返しうる語 (queued/waiting 等) の綴りは未確認。

### DA-31 WABI 停止時、結果ページが無反応になる
- **ページ/機能**: Diff Analysis Result > Status / Download Result (バックエンド停止時)
- **旧 (chip-atlas.org)**: Status 欄に「server unavailable」が表示され、ポーリングは継続。Download Result の URL テキストはクライアント側で組み立てるため常に表示。(旧 JS の `alert("No response from the DDBJ supercomputer system: please note the result URL…")` は `status == "unavailable"` と比較しているため、実際の応答「server unavailable」では発火しない = 旧のバグ。)
- **新 (localhost:9292)**: `/jobs/:id/status` が 503 (`status:"backend_unavailable"`) を返すが、`client.ts` の `request()` が非 2xx を例外にするため `FAILED_STATUSES` の `backend_unavailable` 判定に到達せず、`console.warn` して再ポーリングするだけ。Status 欄は「Requesting」(または直前の値) のまま、画面に何も出ない。`/jobs/:id/result` も 503 のため Download Result 欄は空 (URL を控える手がかりも無い)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:470-473, old-app/public/js/pj/diff_analysis_result.js:9-18, 111-122 / 新: routes/jobs.rb:82-87, 98-100, frontend/api/client.ts:212-219, frontend/components/job-tracker.ts:149-171, 201-225
- **確認方法**: `ソース推定` (WABI 停止状態を再現できないため)
- **備考**: `poll()` の catch で `ApiError.status === 503` を `setStatus(inst, 'backend_unavailable')` にマップする、または `/jobs/:id/status` を 200 で返す、のいずれかで解消。結果 URL は決定的に組み立てられるので 503 時もテキスト表示を維持するのが望ましい。

### DA-32 Download Result リンク (URL 同一、新タブで開く)
- **ページ/機能**: Diff Analysis Result > Download Result
- **旧 (chip-atlas.org)**: `https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/<id>?info=result&format=zip` をテキスト表示、finished で同じ URL を href に付与 (同タブ)。IGV セッション/`.igv_session.xml`/`.igv.bed` へのリンクは **旧にも無い** (JS は `localIgvUrl` を組み立て `a#view-on-igv` に付与しようとするが HAML に該当要素が無い = 未使用コード)。
- **新 (localhost:9292)**: `GET /jobs/:id/result?backend=wabi&type=diff_analysis` → `{"urls":{"zip":"https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/<id>?info=result&format=zip"}}` (curl 確認、旧と同一 URL)。テキストを先に表示し、finished で href + `target="_blank" rel="noopener"`。未リンク時は灰色表示。HTML/TSV/IGV リンクは無し (Enrichment と異なり zip のみ、旧と同じ)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/diff_analysis_result.js:9-18, 29-38, 127-130, old-app/views/diff_analysis_result.haml:63-67 / 新: lib/services/compute_router.rb:78-93, routes/jobs.rb:94-104, frontend/components/job-tracker.ts:142-171, views/diff_analysis_result.erb:34, public/css/style.css:682-688
- **確認方法**: `curl+ソース確認済み`

### DA-33 実行ログ表示: 取得経路・停止条件・プレースホルダ文言・描画方式
- **ページ/機能**: Diff Analysis Result > Execution Log
- **旧 (chip-atlas.org)**: 即時 + 10 秒間隔で `GET /diff_analysis_log?id=` を **ジョブ終了後も永久に** 呼ぶ。404 なら (空のときのみ)「Execution Log / Log file not available yet. Please wait...」、他エラーなら「Execution Log / Fetching log file… The page will refresh automatically.」。取得できたら `<h3>Execution Log</h3><pre><code>` + ログ本文を **innerHTML で挿入** (ログ中の HTML がそのまま解釈される)。高さ制限なし。
- **新 (localhost:9292)**: 即時 + 10 秒間隔で `GET /jobs/:id/log?backend=wabi`。終了ステータス (finished/error 等) 検出後に最後の 1 回を読んで停止。本文が空なら「Log file not available yet. Please wait…」(三点リーダ)、404/503 等の失敗は「Log file not available yet. This page refreshes on its own.」。既にログがあればプレースホルダで上書きしない。描画は `textContent` (HTML 無効化)、`pre` は `max-height:400px` でスクロール、見出しは `h3.h5` (小さめ)。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:374-381, old-app/public/js/pj/diff_analysis_result.js:132-168 / 新: routes/jobs.rb:107-122, lib/services/wabi_service.rb:139-149, frontend/components/job-tracker.ts:227-278, 206-220; `curl localhost:9292/jobs/test123/log?backend=wabi` → 404
- **確認方法**: `curl+ソース確認済み` (実ログの描画は要実ジョブ確認)
- **備考**: 旧はログ本文が HTML として解釈される点で XSS 経路でもある (SEC 担当の範囲)。

### DA-34 結果ページの meta description
- **ページ/機能**: Diff Analysis Result > `<meta name="description">`
- **旧 (chip-atlas.org)**: 「Display the results of diff analysis.」
- **新 (localhost:9292)**: 「Job status and downloads for a submitted diff analysis.」(`<title>` は同一「ChIP-Atlas: Diff Analysis Result」)
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/diff_analysis_result.haml:8 / 新: views/diff_analysis_result.erb:3, views/layout.erb:6
- **確認方法**: `curl+ソース確認済み`

### DA-35 メッセージ提示の一元化 (alert → `#submit-status` aria-live)
- **ページ/機能**: Diff Analysis > Submit 下の状態行
- **旧 (chip-atlas.org)**: 例外的事象はすべて `alert()` (利用不可・推定失敗・投入失敗)。通常時の状態表示は無し。
- **新 (localhost:9292)**: `#submit-status` (`text-muted small`, `aria-live="polite"`) に「Submitting…」「Submit failed…」「No example data available…」「Failed to load example data.」「Both datasets must contain…」を表示。スクリーンリーダにも通知。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 新: views/diff_analysis.erb:89, frontend/pages/diff-analysis.ts:322, 329, 333, 337, 352, 370, 382
- **確認方法**: `curl+ソース確認済み`

---

## 新旧で差が無いことを確認した項目 (参考)
- h1「ChIP-Atlas: Diff Analysis」、`<title>` 2 ページとも同一。ⓘ の個数 (3) と文言。既定タイトル値 (My project / dataset A / dataset B)。
- 「node status (epyc.q)」リンク (URL `https://sc.ddbj.nig.ac.jp/en/operation/job_queue_status/`、target=_blank) — 新は rel=noopener 追加のみ。
- 「Estimated run time:」ラベル、「N mins」形式 (旧新とも「hr」表記に切り替えない)。
- Estimated の式・丸め (DA-19 の入力差を除く)。WABI へ渡るキー集合と定数 (DA-24)。
- 「Result page URL will be available for a week…」文、Status 初期値「Requesting」、脚注文 (句点のみ差)。
- 結果ページに「Copy URL」ボタンは新旧とも無い。IGV セッションリンクも新旧とも無い。

## 要ブラウザ確認リスト
1. DA-01/02: 新版で警告 `#unavailable-notice` が常時表示され Submit が disabled になっている実画面。
2. DA-06: タブクリックで `#genome=` が書き込まれ、再読込で復元されること。旧形式ハッシュ・`#genome=hg19` で先頭タブに戻ること。
3. DA-07/11: 新版でラジオが全ゲノム共通であること (hg38 で DMR → mm10 でも DMR 表示、mm10 の textarea は残る)。
4. DA-12: 旧 (本番) でタブを往復するとタイトル欄が既定値に戻るか (Bootstrap 3 の `li.active` 同期更新前提)。
5. DA-13: ce11 + Bisulfite-seq で旧は「no public data available」置換・placeholder 消去、新はクリック後メッセージ。TAIR12 での「No example data available…」。
6. DA-14: ポップオーバーの配置・`\n` の扱い (1 段落に潰れないか)・キーボード focus で開くか。
7. DA-16/17/18/29: カード・小型入力・全幅ボタン・「—」・テーブル th 太字 30%・脚注の見た目。
8. DA-18: 500 ms デバウンス、ID 0 件で「—」、失敗時「(failed)」。旧で空 textarea クリック時に「12 mins」が出ること。
9. DA-22: 応答待ち中の再クリックで二重投入されるか (投入禁止のためモック環境でのみ)。
10. DA-26: `?id=x` のみ / `?id=x&backend=wabi` / 旧形式 URL での結果ページ表示 (エラー alert とテーブル非表示)。
11. DA-27/28/30/33: 実ジョブ (投入可能になった後) で Submitted at の復元、Status 語彙と色、finished 後のログ停止、ログの max-height スクロール。
12. DA-31: WABI 停止時 (または `/jobs/:id/status` を 503 に固定したモック) で Status 欄が「Requesting」のまま止まること。

## 未確認・不確実事項
- **WABI が Diff Analysis (antigenClass=diffbind/dmr) を現在受け付けるか** (DA-01)。本番・ローカルとも投入禁止のため未検証。compute_router.rb のコメント (WABI は提供していない) の根拠も不明。オーナーに確認必須。
- DA-19: 回帰式の定数が本番の二重加算 X で当てはめられたものかどうか。dm6/dm3・ce11/ce10 の重複行は未実測 (hg/mm のみ本番 API で確認)。
- DA-27: WABI リクエスト ID の時刻書式 (JST) はテストに記載の実ジョブ 2 件に基づく推定。
- DA-30: WABI `?info=status` が返す語彙 (running / queued / waiting / error …) の実物。旧の「`format=html` が 200 = finished」判定が Diff Analysis (成果物は zip) でも正しく機能しているかも未検証。
- DA-24: `WabiService` 経由の form-encode 結果が旧の `Net::HTTP.post_form` と byte 一致するか (整数 `permTime`/`threshold` の文字列化は同等と推定)。
- DA-26: 新版のリダイレクトが `encodeURIComponent` するため、`title` に `+` や `%` を含む場合の往復 (テストは `&`/`=` のみ)。
- 旧 `alert()` の文言は JS ソースからの引用であり、本番ブラウザでの表示は未確認 (JS は md5 一致)。
- 新版のタイトル入力の許容文字 (ヘルプ文) を WABI 側がどう扱うかは新旧とも不明。
