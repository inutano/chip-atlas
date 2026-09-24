# Target Genes (設定ページ / 結果ページ / ダウンロード) 新旧比較 — 担当接頭辞 TG

## 担当範囲の要約

- 対象: 旧 `/target_genes` (HAML + jQuery typeahead + `<select size=8>`) と、旧結果ページ = chip-atlas.dbcls.jp 上の事前生成 HTML (`/data/<genome>/target/<antigen>.<distance>.html`)。新 `/target_genes` (ERB + TypeScript combobox + list box) と、新結果ページ `/target_genes_result` (アプリ内描画、`/api/target_genes` を 100 行ずつページング)。
- 設定ページの見出し・パネル名・距離ラベル (±1k/±5k/±10k)・既定値 (±1k)・ボタン文言・Tutorial 3 リンクは文言一致。リード文の末尾ピリオドと meta description のみ差。
- ゲノムタブは 10 → 7 (hg19/mm9/dm3/ce10 削除、TAIR12 追加)。共通 6 ゲノムの antigen 一覧は本番 `/data/target_genes_analysis.json` と件数・内容・順序とも完全一致 (hg38 1,766 / mm10 869 / rn6 67 / dm6 263 / ce11 162 / sacCer3 67)。`wdr-5` の死にエントリは両者共通。
- 結果データは同じ TSV が源泉で、mm10/Stat3 ±1kb の上位 10 遺伝子と値は新旧一致。ただし旧 HTML は上位 1,000 行に切り詰め、新は全 13,459 行を閲覧可能 (改良)。
- 新で失われた機能: 遺伝子ごとの「↻」リンク (その遺伝子自身の Target Genes ページへ)、STRING DB へのリンク (列見出し + 各行)、セルの hover ツールチップ、結果ページの Movie/Document リンク、旧 `?base=` リダイレクト。
- 新で加わった機能: サーバサイド遺伝子名検索、任意列の昇降順ソート、距離切替のその場再読込、ページング、数値の表示、`#genome=` ディープリンク、JSON API。
- 退行 2 件: (1) list box の先頭行が選択表示なのに内部状態は未選択で、そのまま View を押すと alert になる (旧は先頭 antigen が自動選択され即送信可)。(2) 設定ページの Download (TSV) はデータ無しのとき生 JSON `{"error":"File not found"}` へ遷移してしまう (旧は alert で留まる)。
- データ差分で影響大: hg38 の一部 antigen (CTCF 等) は上流 TSV がヘッダ行のみ (47,217 bytes, 3 距離とも) で、新旧とも空。新側のバグではなく上流データ。
- 分類集計: 改良 9 / 単なる変更 16 / 機能削除 5 / 退行 (要修正) 2 / データ差分 4 / 新機能 6 (計 42 件)。

---

## 設定ページ (/target_genes)

### TG-01 ゲノムタブの構成 (10 → 7)
- **ページ/機能**: Target Genes > ゲノムタブ
- **旧 (chip-atlas.org)**: `H. sapiens (hg38)` `H. sapiens (hg19)` `M. musculus (mm10)` `M. musculus (mm9)` `R. norvegicus (rn6)` `D. melanogaster (dm6)` `D. melanogaster (dm3)` `C. elegans (ce11)` `C. elegans (ce10)` `S. cerevisiae (sacCer3)` の 10 タブ。初期タブ hg38。
- **新 (localhost:9292)**: `hg38 / mm10 / rn6 / dm6 / ce11 / sacCer3 / A. thaliana (TAIR12)` の 7 タブ (ラベル書式は同じ)。初期タブ hg38。TAIR12 は 77 antigen (AGL20, AGO1, … LFY …)。上流には TAIR12 のデータファイルが存在し (`https://chip-atlas.dbcls.jp/data/TAIR12/target/LFY.1.html` → 200)、新 API で `TAIR12/LFY/1` は 11,298 行返る。
- **分類**: `データ差分`
- **影響度**: 高
- **根拠**: 旧: `curl https://chip-atlas.org/target_genes` の `<ul class="nav nav-tabs">`、old-app/views/target_genes.haml:55-59 / 新: `curl http://localhost:9292/target_genes` 内 `#page-data` JSON、routes/pages.rb:67-71
- **確認方法**: `curl+ソース確認済み`
- **備考**: BRIEF の「意図的変更」と一致。旧版で hg19/mm9/dm3/ce10 を使っていた利用者には、対応する antigen 数 (hg19 1,766 / mm9 873 / dm3 249 / ce10 162) 分の入口が消える。

### TG-02 antigen 一覧 (index) の一致状況
- **ページ/機能**: Target Genes > 1. Choose Antigen の候補一覧
- **旧 (chip-atlas.org)**: `/data/target_genes_analysis.json` (49,516 bytes)。genome → antigen 配列。JS 側で `options.sort()` (コードポイント順) してから `<select>` に追加。
- **新 (localhost:9292)**: `/api/target_genes_index` (25,858 bytes)。同じ形 (genome → antigen 配列)。共通 6 ゲノムについて件数・集合・並び順とも完全一致 (差分 0)。
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 両 JSON を Python で集合比較 (only-prod / only-local とも 0 件、`sorted? True` を両側で確認)。旧: old-app/public/js/pj/target_genes.js:113、old-app/lib/pj/analysis.rb:74-83 / 新: lib/models/analysis.rb:105-114、routes/api.rb:121-124
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新は `target_genes_result` でソートしておらず DB の挿入順 (= 上流 analysisList.tab の行順) をそのまま返す。現在は上流ファイルが整列済みなので一致しているが、上流の行順が変わると list box の並びも変わる (旧は JS で必ずソート)。ページ側 (frontend/pages/target-genes.ts:46, autocomplete.ts:200-206) もソートしない。

### TG-03 `wdr-5` (ce11) の死にエントリ
- **ページ/機能**: Target Genes > antigen 一覧 (ce11)
- **旧 (chip-atlas.org)**: ce10/ce11 に `wdr-5` が載るが `https://chip-atlas.dbcls.jp/data/ce11/target/wdr-5.1.html` は 404。View を押すと `/api/remoteUrlStatus` が非 200 を返し、alert「No data found: …」で設定ページに留まる。
- **新 (localhost:9292)**: ce11 に同じ `wdr-5` が載る。`/api/target_genes?genome=ce11&track=wdr-5&distance=1` → 404 `{"error":"Target genes data not found"}`。結果ページへ遷移してから赤い alert 「Failed to load target genes. …」が出る (TG-38)。
- **分類**: `データ差分`
- **影響度**: 低
- **根拠**: 両 index JSON に `wdr-5` あり (ce11)、上流 HEAD 404、`curl http://localhost:9292/api/target_genes?genome=ce11&track=wdr-5&distance=1&limit=1`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 上流の命名 (`wdr-5.1` 遺伝子) 由来で新旧同条件。docs/superpowers/plans/2026-09-18-post-parity-fixes-outcome.md:124-128 の記述は実物で確認できた。

### TG-04 hg38 の一部 antigen は上流 TSV がヘッダのみ (CTCF 等)
- **ページ/機能**: Target Genes > hg38 結果
- **旧 (chip-atlas.org)**: `https://chip-atlas.dbcls.jp/data/hg38/target/CTCF.1.tsv` は 47,217 bytes・1 行 (2,209 列のヘッダのみ)。`.5` `.10` も同サイズ。`CTCF.1.html` は 836,842 bytes で見出し行のみの空行列 (推定: 行数 0 でこのサイズ = ヘッダ 2,209 セル分)。`AATF.1.tsv` は 168 bytes (3 行)。`STAT3.1.tsv` は 5.0 MB (14,079 行) で正常。
- **新 (localhost:9292)**: `/api/target_genes?genome=hg38&track=CTCF&distance=1` → `columns: 2209, total: 0`。結果ページは見出し行 + 「No target genes found」「Page 1 of 1」を表示 (frontend/pages/target-genes-result.ts:324-338)。
- **分類**: `データ差分`
- **影響度**: 高
- **根拠**: 上流 HEAD (Content-Length 47217 ×3、Last-Modified 2025-02-02)、`curl -r 0-60000 …CTCF.1.tsv | wc -l` → 1、ローカル API 3 距離とも total 0
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新アプリのバグではない (DataProxy はボディをそのまま返し、TargetGenesTsv は行数 0 を素直に返す)。ただし利用頻度最高の hg38/CTCF が空なのは本番でも同じ。docs/ui-parity-audit-2026-09-14.md:234 の「hg38 が index に無い」は解消済み (1,766 件あり) で、残る問題は上流ファイル側。上流に確認を推奨。どの antigen が空かは網羅未確認 (末尾参照)。

### TG-05 リード文の末尾ピリオド
- **ページ/機能**: Target Genes > ページ見出し下の説明文
- **旧 (chip-atlas.org)**: 「Search for genes bound by given transcription factors」(ピリオド無し)
- **新 (localhost:9292)**: 「Search for genes bound by given transcription factors.」(ピリオド有り、`p.main-desc`)
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/target_genes.haml:34-35 / 新: views/target_genes.erb:10、views/_page_header.erb:20-22
- **確認方法**: `curl+ソース確認済み`

### TG-06 meta description の変更
- **ページ/機能**: Target Genes > `<meta name="description">`
- **旧 (chip-atlas.org)**: 「Prediction of potential target genes of transcription factors based on experimental results.」
- **新 (localhost:9292)**: 「Search for genes bound by given transcription factors.」
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/target_genes.haml:8 / 新: views/target_genes.erb:3
- **確認方法**: `curl+ソース確認済み`
- **備考**: 検索エンジンのスニペットにのみ影響。`<title>` は両者「ChIP-Atlas: Target Genes」で一致。

### TG-07 Tutorial ドロップダウン
- **ページ/機能**: Target Genes > 右上 Tutorial
- **旧 (chip-atlas.org)**: `div.button.btn.btn-primary.dropdown-toggle` (div 要素) に「Tutorial」+ caret。項目 PDF / Movie / Movie (統合TV, Japanese) (`target="_blank"`)。
- **新 (localhost:9292)**: `<button class="btn btn-primary dropdown-toggle">`、同じ 3 項目・同じ URL、`rel="noopener noreferrer"` 追加、`dropdown-menu-end` で右寄せ。col-md-10 / col-md-2 の配置は旧と同じ。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/target_genes.haml:37-49 / 新: views/target_genes.erb:11-15、views/_page_header.erb:13-30、curl 結果
- **確認方法**: `curl+ソース確認済み` (位置は `要ブラウザ確認`)
- **備考**: docs/ui-parity-audit-2026-09-14.md の「Tutorial button placement が下にずれる」は現行ソース (_page_header の row 配置) では解消されているはず。

### TG-08 antigen 入力 UI (typeahead + list box) の挙動
- **ページ/機能**: Target Genes > 1. Choose Antigen
- **旧 (chip-atlas.org)**: typeahead.js (Bloodhound, whitespace tokenizer, `minLength: 1`, 候補 15 件、`hint: true`/`highlight: true`) の入力欄 + `<hr>` + 全 antigen を載せた `<select size="8">` (クラス `flexselect` が付くが `.flexselect()` はどこからも呼ばれておらず素の list box)。list box は入力で絞り込まれない。入力欄で候補選択/キー入力すると、値が一覧に完全一致する場合だけ `<select>` の選択を同期 (target_genes.js:152-157)。list box をクリックしても入力欄は変わらない。ゲノムタブごとに独立した入力欄と list box。
- **新 (localhost:9292)**: `role=combobox` の入力欄 + 直下に list box (`<select size="8">`, id `track-input-list-box-select`)。部分一致・大文字小文字無視で最大 50 件のドロップダウン (フォーカスしただけで先頭 50 件が開く)。list box は入力に合わせてリアルタイムに絞り込まれ、list box で選ぶと入力欄にその値が入る。↑↓/Enter/Esc 対応。ゲノム切替で入力欄を空にし一覧を差し替える (単一パネル)。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/views/target_genes.haml:72-74,107-112、old-app/public/js/pj/target_genes.js:129-158、`grep flexselect()` が old-app/public/js/pj/ で 0 件 / 新: frontend/components/autocomplete.ts:24,55-76,120-125,164-198、frontend/components/list-box.ts:31-34、frontend/pages/target-genes.ts:43-55
- **確認方法**: `ソース推定` (Bloodhound の一致方式はトークン前方一致と推定、実行未確認) + `要ブラウザ確認` (フォーカス時に開くドロップダウンが list box に被る見え方)
- **備考**: 旧では「tat3」で Stat3 は出ないが新では出る (部分一致)。候補上限は 15 → 50。`hint` (灰色の先読み表示) は無くなった。

### TG-09 list box の初期選択表示と内部状態の不一致 (View が alert になる)
- **ページ/機能**: Target Genes > 1. Choose Antigen → View Potential Target Genes
- **旧 (chip-atlas.org)**: 一覧生成時に先頭 antigen に `selected` を付ける (target_genes.js:113-120) ので、何も触らず View を押しても先頭 antigen (hg38 なら AATF) で結果へ進める。`retrievePostData` は常に `<select>` の選択値を読む。
- **新 (localhost:9292)**: `ListBox.setOptions` が先頭行を `selected=true` にして青くハイライトするが `onChange` は発火せず、`currentTrack` は `''` のまま。この状態で View / Download を押すと alert「Select a genome and antigen first.」。さらに、入力欄に antigen 名を最後まで打っても Enter やクリックで確定しなければ `currentTrack` は空のままで同じ alert になる (旧は keyup で同期していた)。逆に list box で選んだ後に入力欄を消しても `currentTrack` は前の値のまま。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 新: frontend/components/list-box.ts:67-69 (先頭選択のみ、onChange 無し)、frontend/components/autocomplete.ts:174-188 (onSelect は menu 選択/list change 時のみ)、frontend/pages/target-genes.ts:46-49 (ゲノム切替で `currentTrack=''`)、:59-63 / 旧: old-app/public/js/pj/target_genes.js:110-127,152-157,160-175
- **確認方法**: `ソース推定` + `要ブラウザ確認`
- **備考**: 修正案: (a) `Autocomplete.setItems` 後に list box の `value` を `currentTrack` に反映する、または View 時に `listBox.value` / 入力欄の完全一致値をフォールバックとして読む。(b) 入力欄の `input` イベントで完全一致時に `currentTrack` を同期。見た目に「選ばれている」のに alert が出るのは利用者を戸惑わせる。

### TG-10 未選択時のバリデーション文言
- **ページ/機能**: Target Genes > View / Download ボタン押下時
- **旧 (chip-atlas.org)**: 未選択状態が存在しない (TG-09)。データが無い場合のみ alert「No data found:\n\nTarget gene analysis data is not available with this condition. Please change the distance from TSS or select another antigen.」、通信失敗時 alert「error!」。
- **新 (localhost:9292)**: alert「Select a genome and antigen first.」(ブロッキング alert)。通信は発生しないので「error!」相当は無い。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/target_genes.js:72-74,81 / 新: frontend/pages/target-genes.ts:60-62,69-71
- **確認方法**: `curl+ソース確認済み` (配信 JS `/js/target-genes.js` に同文言を確認)

### TG-11 距離ラジオボタン
- **ページ/機能**: Target Genes > 2. Choose Distance from TSS
- **旧 (chip-atlas.org)**: ラベル「±1k」「±5k」「±10k」(前後に空白)、既定 ±1k、ゲノムごとに独立した radio group (`hg38DistanceOption` 等) なのでタブを変えると ±1k に戻る。
- **新 (localhost:9292)**: ラベル「±1k」「±5k」「±10k」、既定 ±1k、単一の radio group (`name="distance"`) なのでゲノムを切り替えても選択が保持される。`<label for>` で関連付け。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/target_genes.haml:82-94 / 新: views/target_genes.erb:35-46、frontend/pages/target-genes.ts:28-31
- **確認方法**: `curl+ソース確認済み`

### TG-12 送信ボタンの状態表示
- **ページ/機能**: Target Genes > View Potential Target Genes / Download (TSV)
- **旧 (chip-atlas.org)**: 文言同じ。押下中は `disabled` にし、POST 完了で戻す (2 リクエスト待ちの間クリック不可)。
- **新 (localhost:9292)**: 文言同じ (`btn-primary btn-lg btn-block`、`d-grid gap-2`)。押下で即遷移し、disabled 制御は無い。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/target_genes.haml:99-100、target_genes.js:40-41,83-85 / 新: views/target_genes.erb:54-55、frontend/pages/target-genes.ts:59-77
- **確認方法**: `curl+ソース確認済み`

### TG-13 View 押下後の遷移先 (外部静的 HTML → アプリ内結果ページ)
- **ページ/機能**: Target Genes > View Potential Target Genes
- **旧 (chip-atlas.org)**: `POST /target_genes?type=submit` (JSON `{condition:{genome,antigen,distance}}`) → `{url}` → `GET /api/remoteUrlStatus?url=` で存在確認 → 200 なら `window.open(url,"_self")` で **chip-atlas.dbcls.jp の静的 HTML** (`/data/<genome>/target/<antigen>.<distance>.html`) へ同一タブ遷移 (ナビバー無し・別オリジン)。非 200 なら alert (TG-10) で留まる。
- **新 (localhost:9292)**: `/target_genes_result?genome=<g>&track=<antigen>&distance=<d>` へ遷移 (アプリ内、ナビバー/フッタ付き、GET のみ、事前存在確認なし)。
- **分類**: `改良`
- **影響度**: 高
- **根拠**: 旧: old-app/public/js/pj/target_genes.js:54-87、old-app/app.rb:308-314,503-505、old-app/lib/pj/location.rb:88-99 / 新: frontend/pages/target-genes.ts:64-65、routes/pages.rb:73-82
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧 URL (chip-atlas.dbcls.jp の静的ファイル) は今後も直接アクセス可能なので、論文等で引用済みのリンクは壊れない。

### TG-14 Download (TSV) の配信方式
- **ページ/機能**: Target Genes > Download (TSV)
- **旧 (chip-atlas.org)**: `POST /target_genes?type=tsv` → 存在確認 → `window.open("https://chip-atlas.dbcls.jp/data/mm10/target/Stat3.1.tsv","_self")`。上流は `Content-Type: text/tab-separated-values`、`Content-Disposition` 無し (ブラウザ依存でダウンロード扱い、ファイル名は URL 由来 `Stat3.1.tsv` と推定)。
- **新 (localhost:9292)**: `window.location.href = /api/target_genes/download?genome=mm10&track=Stat3&distance=1&format=tsv` → アプリが上流から取得して `Content-Type: text/tab-separated-values;charset=utf-8`、`Content-Disposition: attachment; filename="Stat3.1.tsv"` で返す。バイト数は上流と同一 (4,094,463)。所要 0.53 s (直接 0.19 s)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: target_genes.js:46-51,70、`curl -I …Stat3.1.tsv` / 新: frontend/pages/target-genes.ts:68-77、routes/api.rb:215-227、`curl -D - …/api/target_genes/download?…&format=tsv`
- **確認方法**: `curl+ソース確認済み` (旧のブラウザ挙動は `要ブラウザ確認`)
- **備考**: 新は `format` 必須 (`type=` ではない)。`format=html` は 400 `Unknown format: html. Available: tsv`。

### TG-15 Download (TSV) でデータが無いとき生 JSON へ遷移する
- **ページ/機能**: Target Genes > Download (TSV) (例: ce11 / wdr-5)
- **旧 (chip-atlas.org)**: 存在確認で非 200 → alert「No data found: …」、ページに留まる。
- **新 (localhost:9292)**: `window.location.href` で `/api/target_genes/download?…` へ遷移するため、404 のときブラウザに `{"error":"File not found"}` (application/json) がそのまま表示され、設定ページから離れる。戻るボタンが必要。
- **分類**: `退行 (要修正)`
- **影響度**: 低
- **根拠**: 新: frontend/pages/target-genes.ts:76、`curl -D - "http://localhost:9292/api/target_genes/download?genome=ce11&track=wdr-5&distance=1&format=tsv"` → 404 JSON / 旧: target_genes.js:64-77
- **確認方法**: `curl+ソース確認済み`
- **備考**: 修正案: 遷移前に `fetch(HEAD)` か `/api/remote_url_status` で確認して無ければ alert/インライン警告、または 404 時に HTML のエラーページを返す。

### TG-16 ゲノムタブの `#genome=` ディープリンク
- **ページ/機能**: Target Genes > ゲノムタブ
- **旧 (chip-atlas.org)**: URL にタブ状態は残らない (常に hg38 で開く)。
- **新 (localhost:9292)**: タブ選択で `history.replaceState` により `/target_genes#genome=mm10` に書き換わり、そのハッシュ付き URL を開くとそのタブで始まる。初期表示でも `#genome=hg38` が付く。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: frontend/components/genome-tabs.ts:8-30,62-70,79-82
- **確認方法**: `ソース推定`

### TG-17 旧 `/target_genes_result?base=<url>` (存在確認付きリダイレクト) の廃止
- **ページ/機能**: Target Genes > 結果 URL
- **旧 (chip-atlas.org)**: `GET /target_genes_result?base=<url>` は `remotefile_available?` で確認して `redirect` (無ければ 404 `not_found`)。旧 JS からは使われていない (直接 `window.open`)。
- **新 (localhost:9292)**: `/target_genes_result` は `genome`/`track` 必須。`base=` 付き旧形式 URL は「Missing genome or track parameter in URL.」の赤い alert になる。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: old-app/app.rb:316-323、`grep target_genes_result old-app/views old-app/public/js` → 呼び出し 0 件 / 新: frontend/pages/target-genes-result.ts:48-55,522-530
- **確認方法**: `curl+ソース確認済み`
- **備考**: 外部ブックマーク経由の利用があったかは不明 (末尾参照)。

### TG-18 index/距離 API のパス変更
- **ページ/機能**: Target Genes > 設定ページが呼ぶ API
- **旧 (chip-atlas.org)**: `GET /data/target_genes_analysis.json`、`GET /data/list_of_genome.json`、`POST /target_genes?type=submit|tsv`、`GET /api/remoteUrlStatus`。
- **新 (localhost:9292)**: `GET /api/target_genes_index` (同形式)、`GET /api/target_genes_distances` (`[{"id":"1","label":"1 kb"},{"id":"5","label":"5 kb"},{"id":"10","label":"10 kb"}]`; ページからは未使用で距離は ERB に固定)、genome 一覧は ERB 埋め込み `#page-data`。POST は無い。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/app.rb:113-145、target_genes.js:8-20 / 新: routes/api.rb:121-129、views/target_genes.erb:6、frontend/api/client.ts:326-332
- **確認方法**: `curl+ソース確認済み`
- **備考**: BRIEF の意図的変更 (`/data/*` → `/api/*`)。

### TG-19 index 読み込み失敗時の表示
- **ページ/機能**: Target Genes > 1. Choose Antigen
- **旧 (chip-atlas.org)**: `$.ajax` の `error` 未定義。失敗すると一覧が空のまま、メッセージ無し。
- **新 (localhost:9292)**: `console.warn('Failed to load target genes index:')` のみ。一覧空、メッセージ無し。読み込み中インジケータも両者無し。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: target_genes.js:8-36 / 新: frontend/pages/target-genes.ts:36-40
- **確認方法**: `ソース推定`

---

## 結果ページ (旧: chip-atlas.dbcls.jp 静的 HTML / 新: /target_genes_result)

### TG-20 ページの器 (外部静的ページ → アプリ内ページ)
- **ページ/機能**: Target Genes 結果ページ全体
- **旧 (chip-atlas.org)**: `<title>ChIP-Atlas | Target genes</title>`、`<h1>ChIP-Atlas: Target genes</h1>`、`<h2>Potential target genes for Stat3</h2>`。ナビバー・フッタ無し、`<FONT face="Helvetica Neue">`、幅固定 3,425 px の `<table id="mainTable">` (mm10/Stat3 の場合)、CSS/JS 依存なし。8.8 MB。
- **新 (localhost:9292)**: `<title>ChIP-Atlas: Target Genes Result</title>`、`<h1>ChIP-Atlas: Target Genes Result</h1>`、要約行「Stat3 on mm10 — TSS ± 1 kb」。共通ナビバー/フッタ、Bootstrap5 テーブル、`table-responsive` 内横スクロール。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: `curl -r 0-8000 https://chip-atlas.dbcls.jp/data/mm10/target/Stat3.1.html` / 新: views/target_genes_result.erb:2,8-9、frontend/pages/target-genes-result.ts:384-386、`curl http://localhost:9292/target_genes_result?genome=mm10&track=Stat3&distance=1`
- **確認方法**: `curl+ソース確認済み`

### TG-21 ヘッダ情報行の文言
- **ページ/機能**: 結果ページ > 表の上の情報
- **旧 (chip-atlas.org)**: 「**Query protein:** Stat3」「**Distance from TSS:** ± **1 kb**  ± 5 kb  ± 10 kb」(他距離は灰色リンク)「**Sort key:** Stat3 | Average」「**Color legends**」+ 色表 (1000 / 750 / 500 / 250 / 1 / 0) + 「(Values = Binding scores of MACS2 and STRING)」「**Download:** TSV (text)」「**Links:** Movie and Document for ChIP-Atlas Target Genes」。
- **新 (localhost:9292)**: 要約行「Stat3 on mm10 — TSS ± 1 kb」、「Distance from TSS:」+ ボタン群「± 1 kb / ± 5 kb / ± 10 kb」、右端「Download TSV」ボタン、検索欄 (TG-31)、「**Color legend** (binding scores of MACS2 and STRING)」+ 色見本 (0 / 1 / 250 / 500 / 750 / 1000+)。Sort key の文字行は無く、列見出しの ↓/↑ 矢印で示す。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: 上記 HTML 先頭部 / 新: views/target_genes_result.erb:8-52、target-genes-result.ts:172-175
- **確認方法**: `curl+ソース確認済み`

### TG-22 結果ページの「Links: Movie / Document」削除
- **ページ/機能**: 結果ページ > Links 行
- **旧 (chip-atlas.org)**: 「Movie」→ https://youtu.be/UBOyoTlDAH4、「Document」→ https://github.com/inutano/chip-atlas/wiki#5-target-genes、「ChIP-Atlas」→ http://chip-atlas.org、「Target Genes」→ http://chip-atlas.org/target_genes (すべて別タブ)。
- **新 (localhost:9292)**: 相当する行・リンク無し。Tutorial ドロップダウンも結果ページには無い。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: Stat3.1.html 先頭部 `<b>Links: </b>…` / 新: views/target_genes_result.erb 全体に該当なし
- **確認方法**: `curl+ソース確認済み`
- **備考**: 設定ページの Tutorial (PDF/Movie) で代替はできるが、結果ページからの導線は失われた。意図的かは不明。

### TG-23 表示行数: 上位 1,000 行固定 → 全行ページング
- **ページ/機能**: 結果ページ > 表本体
- **旧 (chip-atlas.org)**: HTML には **1,000 行** (mm10/Stat3 ±1kb: TSV 13,459 行のうち Average 降順上位 1,000) しか含まれず、残りは TSV でしか見られない。行数表示なし。
- **新 (localhost:9292)**: 全 13,459 行を 100 行/ページで閲覧。「Showing 1 to 100 of 13,459 genes」「Page 1 of 135」。上位 10 遺伝子 (Stat3, Rpl22, Sbno2, Skap2, Jak3, Vps28, Gtf2a2, B3gntl1, Psmd3, Trappc2l) と値は旧 HTML / TSV と一致。
- **分類**: `改良`
- **影響度**: 高
- **根拠**: 旧: 全文取得 (8,791,919 bytes) を解析 → `mainTable` 内 `<tr>` 1,001 (見出し 1 + 1,000) / 新: `/api/target_genes?genome=mm10&track=Stat3&distance=1&limit=10`、target-genes-result.ts:16,330-338
- **確認方法**: `curl+ソース確認済み`

### TG-24 ページング操作は Previous / Next のみ
- **ページ/機能**: 結果ページ > ページング
- **旧 (chip-atlas.org)**: 単一ページ (ページングなし)。
- **新 (localhost:9292)**: 「Previous」「Page x of y」「Next」のみ。ページ番号ジャンプ・ページサイズ変更・全件表示は無い (ページサイズ 100 固定、API 上限 500)。ページ移動でスクロール位置は戻らない。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: views/target_genes_result.erb:78-87、target-genes-result.ts:476-489、lib/services/target_genes_tsv.rb:66-67
- **確認方法**: `curl+ソース確認済み`
- **備考**: 135 ページを順送りするしかないので、深い順位の遺伝子には検索欄 (TG-31) で到達する設計。

### TG-25 セルに数値を表示
- **ページ/機能**: 結果ページ > スコアセル
- **旧 (chip-atlas.org)**: 25×25 px の色セルのみ。数値はどこにも表示されない (hover の title は「細胞種\n(SRX)\n\n遺伝子名」で値ではない)。値を知るには TSV が必要。
- **新 (localhost:9292)**: 背景色 + 数値 (整数はそのまま「665」、小数は 2 桁「1021.21」; TSV は 1021.206107)。背景の明度に応じて文字色を黒/白に自動切替。`tabular-nums`。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: Stat3.1.html 末尾の `<script>` (title 生成)、行セル `<td align="center" bgcolor="#ff0000" …></td>` / 新: target-genes-result.ts:96-103,275-283、public/css/style.css:617-621
- **確認方法**: `curl+ソース確認済み` (配色の可読性は `要ブラウザ確認`)

### TG-26 色スケールと凡例の並び
- **ページ/機能**: 結果ページ > Color legend / セル色
- **旧 (chip-atlas.org)**: 凡例 1000 (#ff0000) / 750 (#ffff00) / 500 (#00ff00) / 250 (#00ffff) / 1 (#0000ff) / 0 (#808080) の降順。セル色は値ごとの連続グラデーション (1,000 行中 951 色)。
- **新 (localhost:9292)**: 同じ 5 停止点 + 0 灰 + 「1000+」赤の昇順表示。線形補間で旧とほぼ同色 (Rpl22 Average 577.95: 旧 #4fff00 / 新 #50ff00 — 丸め差 ±1)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: 凡例 `<table>` と行 2 の `bgcolor="#4fff00"` / 新: views/target_genes_result.erb:42-50、target-genes-result.ts:66-94
- **確認方法**: `curl+ソース確認済み`

### TG-27 実験列 (SRX ごとの列) が既定で非表示
- **ページ/機能**: 結果ページ > 表の列構成
- **旧 (chip-atlas.org)**: 遺伝子 / ↻ / Average / 131 本の実験列 / STRING を最初から全部表示 (ヒートマップとして一望できる)。
- **新 (localhost:9292)**: 既定は「Gene / Average / STRING」の 3 列のみ。`<details>`「Show experiment columns (131)」を開くと 131 列が現れ (開くと「Hide experiment columns (131)」)、説明文「Individual experiments are grouped under the query antigen's Average column above. Expanding adds one column per experiment, already loaded with this page of genes — no extra request is made.」。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 新: views/target_genes_result.erb:60-67、target-genes-result.ts:358-365,513-520、style.css:628-634 / 旧: 見出し行 137 セル
- **確認方法**: `curl+ソース確認済み` (展開時の横スクロール挙動は `要ブラウザ確認`)
- **備考**: 旧の主役だった「どの実験で結合しているか」の一覧性が 1 クリック分後退する。既定で開いておく/前回状態を記憶する案は検討余地あり。

### TG-28 列見出しの文言 (細胞種のアンダースコア)
- **ページ/機能**: 結果ページ > 表の見出し
- **旧 (chip-atlas.org)**: 「**Stat3**'s Target genes」、-45° 回転した「Stat3: Average」「SRX361677: Astrocytes」「SRX15797912: B cells」「Stat3: STRING」(空白は `&nbsp;`)。
- **新 (localhost:9292)**: 「Gene」「Average」(title に「Stat3 | Average」)、「SRX361677: Astrocytes」「SRX15797912: B_cells」「SRX015582: CD4+_T_cells」(TSV 見出しの `_` をそのまま表示)、「STRING」。回転なし、横並び。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: 見出しセル `<nobr>:&nbsp;B&nbsp;cells</nobr>` / 新: target-genes-result.ts:121-125,236-270、API `columns` に `SRX15797912|B_cells`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧 HTML 生成側は `_` を空白に戻していた。新も `_` → 空白の置換を入れると旧と同じ表記になる (修正提案)。

### TG-29 ソート方式
- **ページ/機能**: 結果ページ > 列ソート
- **旧 (chip-atlas.org)**: 各列見出しの「◢」(title「Sort by this column...」) は **別の事前生成 HTML** へのリンク (`SRX361677.1.html`、`STRING_Stat3.1.html`、いずれも約 8.8 MB、「Sort key: SRX361677 | Astrocytes」)。降順のみ。遺伝子名ソートなし。
- **新 (localhost:9292)**: 見出しが `<button>`。クリック/Enter/Space でサーバサイドソート (`sort=<列名>&order=asc|desc`)。同じ列を再クリックで降順↔昇順、矢印 ↓/↑ と `aria-sort`。Gene 列 (文字列) も含め全列ソート可。ページ 1 に戻る。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: 見出しセルの `href="…/SRX361677.1.html"`、`curl -I` で 200 / 新: target-genes-result.ts:146-151,197-227、lib/services/target_genes_tsv.rb:140-158,259-266、`curl …&sort=STRING&order=asc` → 200、`sort=Nope` → 400
- **確認方法**: `curl+ソース確認済み`

### TG-30 距離切替時のソート引き継ぎとフォールバック通知
- **ページ/機能**: 結果ページ > 距離ボタン
- **旧 (chip-atlas.org)**: 別ページへの遷移なので常に Average 降順に戻る。
- **新 (localhost:9292)**: 距離を変えてもソート列を維持。その距離のファイルに無い列だった場合 (API 400) は既定ソートで再取得し、黄色い注記「"SRX…|…" isn't a column at this distance — sorted by the default Average column instead.」を表示。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: target-genes-result.ts:161-168,392-396,433-450、frontend/pages/target-genes-result.test.ts:86-103
- **確認方法**: `ソース推定` (テストは純関数のみ)

### TG-31 遺伝子名検索 (サーバサイド)
- **ページ/機能**: 結果ページ > 「Filter by gene name (e.g. Myc)」
- **旧 (chip-atlas.org)**: 無し (ブラウザの Ctrl+F で 1,000 行の範囲内のみ)。
- **新 (localhost:9292)**: `type="search"`、`maxlength="200"`、300 ms デバウンス、大文字小文字無視の部分一致、全行対象 (ソート/ページの前に適用、`total` は絞り込み後)。例: `q=socs` → total 7 (Socs3 425.70, Socs2 101.27, Socs1 35.52 …)。0 件なら「No genes match "Zzz".」(検索無しの 0 件は「No target genes found」)。200 文字超は切り捨て。
- **分類**: `新機能`
- **影響度**: 高
- **根拠**: views/target_genes_result.erb:23-35、target-genes-result.ts:324-328,497-511、lib/services/target_genes_tsv.rb:75,170-188、`curl …&q=socs&limit=3`
- **確認方法**: `curl+ソース確認済み`

### TG-32 遺伝子ごとの「↻」リンク (その遺伝子の Target Genes ページへ) の削除
- **ページ/機能**: 結果ページ > 各行 2 列目
- **旧 (chip-atlas.org)**: 各行に「↻」(title「Serach this target genes...」[原文ママ])。その遺伝子自身が antigen としてデータを持つ場合はリンク (`…/target/<Gene>.1.html`) — 1,000 行中 78 行が有効、他は灰色。TF → その標的 TF → … と辿れる。
- **新 (localhost:9292)**: 遺伝子名は素のテキスト。リンク無し。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: 行 1 `<td title="Serach this target genes..."><b><a href="https://chip-atlas.dbcls.jp/data/mm10/target/Stat3.1.html">&#x21BB</a>` (有効 78/1000 を集計) / 新: target-genes-result.ts:293-298
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新なら index (`/api/target_genes_index`) に遺伝子名が含まれるか判定して `/target_genes_result?genome=…&track=<gene>&distance=…` へリンクすれば復元できる。

### TG-33 STRING DB へのリンク (列見出し + 各行) の削除
- **ページ/機能**: 結果ページ > STRING 列
- **旧 (chip-atlas.org)**: 見出し「Stat3: STRING」は STRING ネットワーク (`http://string-db.org/newstring_cgi/show_network_section.pl?identifier=10090.ENSMUSP00000120152`) へ、各行の STRING セルは「≫」で antigen × 遺伝子のペアページ (`…identifiers=10090.ENSMUSP00000120152%250D10090.ENSMUSP00000056948`, title「Serach Stat3 and Ier5 in STRING.」) へリンク (1,000 行すべて)。
- **新 (localhost:9292)**: STRING 列は数値 + 色のみ。リンク無し。ENSP ID は TSV に無いので新側では単純に再現できない。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: 見出し末尾セルと行末セル (`&#8811;` 1,000 個) / 新: target-genes-result.ts:247-249,300-303
- **確認方法**: `curl+ソース確認済み`

### TG-34 実験列見出しの /view リンク
- **ページ/機能**: 結果ページ > 実験列見出し
- **旧 (chip-atlas.org)**: SRX ID 自体がリンク (`http://chip-atlas.org/view?id=SRX361677`、`target="_blank"`、title「Open info to SRX361677」)。
- **新 (localhost:9292)**: 見出しはソートボタン。その下に「↗」(aria-label「View experiment SRX361677」) が `/view?id=SRX361677` へ同一タブでリンク。細胞種名はリンクでない。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: 見出しセル / 新: target-genes-result.ts:262-267
- **確認方法**: `curl+ソース確認済み`
- **備考**: 同一タブ遷移は結果ページの状態 (ソート/ページ/検索) を失う (TG-37)。`target="_blank"` 相当に戻す案あり。

### TG-35 セルの hover ツールチップの削除
- **ページ/機能**: 結果ページ > スコアセル
- **旧 (chip-atlas.org)**: ページ末尾の JS が各セルに `title="<細胞種>\n(<SRX>)\n\n<遺伝子>"` を付与。列が回転見出しで読みにくいのを補っていた。
- **新 (localhost:9292)**: セルに title 無し (見出しに title あり)。数値は見えるが、横スクロール中にその列がどの実験かは見出しに戻る必要がある。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: Stat3.1.html 末尾 `<script>` / 新: target-genes-result.ts:275-283
- **確認方法**: `curl+ソース確認済み`

### TG-36 距離切替のその場再読込
- **ページ/機能**: 結果ページ > Distance from TSS
- **旧 (chip-atlas.org)**: 「± 5 kb」「± 10 kb」は別 HTML (各 8.8 MB 級) への灰色リンク。
- **新 (localhost:9292)**: ボタン群 (`active` + `aria-pressed`)。押すとページ 1 から再取得し、URL の `distance=` を `replaceState` で更新。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: views/target_genes_result.erb:11-17、target-genes-result.ts:57-61,367-373,464-474
- **確認方法**: `curl+ソース確認済み`

### TG-37 URL に残る状態の粒度
- **ページ/機能**: 結果ページ > URL / ブックマーク
- **旧 (chip-atlas.org)**: URL = 静的ファイル名で、antigen・距離・ソート列 (例 `SRX361677.1.html`) まで URL に含まれ、そのまま共有可能。
- **新 (localhost:9292)**: `?genome=&track=&distance=` のみ。ソート列・順序・ページ・検索語は URL に入らないので、共有/リロードで初期状態に戻る。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: target-genes-result.ts:57-61
- **確認方法**: `ソース推定`

### TG-38 読み込み中・エラー・空状態の文言
- **ページ/機能**: 結果ページ > 状態表示
- **旧 (chip-atlas.org)**: 読み込み中表示なし (8.8 MB を受信・描画し終わるまで白紙)。データ無しは設定ページ側の alert で防ぐ。URL 直打ちで無いファイルは chip-atlas.dbcls.jp の nginx 404。
- **新 (localhost:9292)**: 「Loading…」→ 表。失敗時 (404/502/通信断すべて同文) 赤 alert「Failed to load target genes. This antigen/genome/distance combination may not have precomputed data.」。パラメータ欠落「Missing genome or track parameter in URL.」。0 行「No target genes found」。検索 0 件「No genes match "…".」。無効な距離 (例 `distance=2`) は 404 → 上記失敗文。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: views/target_genes_result.erb:54-55、target-genes-result.ts:324-328,452-460,522-530、`curl …distance=2` → 404
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧 alert にあった「Please change the distance from TSS or select another antigen.」の行動指針が新には無い。距離ボタンが同じ画面にあるので一文添えると親切。

### TG-39 結果ページからの TSV ダウンロード
- **ページ/機能**: 結果ページ > Download
- **旧 (chip-atlas.org)**: 「Download: TSV (text)」テキストリンク、`target="_blank"` で `.tsv` を開く。
- **新 (localhost:9292)**: 右上の「Download TSV」ボタン (`/api/target_genes/download?…&format=tsv`、attachment、ファイル名 `<track>.<distance>.tsv`)。読み込み失敗時は非表示。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: 先頭部 `<b>Download: </b>` / 新: views/target_genes_result.erb:18-20、target-genes-result.ts:375-382,456
- **確認方法**: `curl+ソース確認済み`

### TG-40 性能 (体感) の差
- **ページ/機能**: 結果ページ > 初回表示・操作
- **旧 (chip-atlas.org)**: mm10/Stat3 ±1kb は 8.8 MB の HTML (1,000 行 × 137 セル、bgcolor 付き) をブラウザが受信・解析・描画。hg38/STAT3 は 10.0 MB。ソートや距離変更のたびに同規模のページを再取得。
- **新 (localhost:9292)**: 初回は JSON 約 70 KB (100 行 × 134 列)。サーバ側は初回に 4 MB の TSV を取得・解析するため cold で約 1.1 s (mm10/Stat1 ±10kb 実測 1.10 s、Stat3 ±1kb 1.13 s)、以後 5 分間はキャッシュで約 6 ms (ソート・ページ・検索も同程度)。TSV 直ダウンロードは経由分 0.53 s (直接 0.19 s)。
- **分類**: `改良`
- **影響度**: 高
- **根拠**: 旧: `curl -I` Content-Length (8,791,919 / 9,972,508) / 新: `curl -w time_total` 実測、lib/services/target_genes_tsv.rb:53-62 (TTL 300 s)
- **確認方法**: `curl+ソース確認済み` (ブラウザ描画時間は `要ブラウザ確認`)
- **備考**: 展開時の 131 列 × 100 行描画、および hg38 CTCF の 2,209 列見出しの描画負荷は未計測。

### TG-41 アクセシビリティ
- **ページ/機能**: 結果ページ全体
- **旧 (chip-atlas.org)**: 回転見出しは `<p id="rotate">` を 130 回以上重複 (無効な HTML)、ARIA 無し、色のみで値を表現、リンクは文字記号 (◢ ↻ ≫) のみ。
- **新 (localhost:9292)**: `aria-sort`、視覚的に隠したソート状態テキスト、`role="img"` + `aria-label` 付き凡例、`aria-pressed` の距離ボタン、`aria-label` 付き ↗ リンク、検索欄の `visually-hidden` ラベル、キーボードでソート可能な `<button>`、数値表示で色に依存しない。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: 見出しセル / 新: views/target_genes_result.erb:23-24,43、target-genes-result.ts:197-227,367-373、style.css:573-608
- **確認方法**: `ソース推定` + `要ブラウザ確認` (スクリーンリーダ)

### TG-42 JSON API (エージェント/スクリプト向け)
- **ページ/機能**: `/api/target_genes`, `/api/target_genes/download`
- **旧 (chip-atlas.org)**: 機械可読な結果 API なし (静的 TSV/HTML を直接取るのみ)。
- **新 (localhost:9292)**: `GET /api/target_genes?genome&track&distance[&sort&order&offset&limit&q]` → `{columns, rows, total, offset, limit}`。`limit` 既定 50・上限 500 (100000 を指定しても 500)。欠落パラメータ 400 `genome, track, and distance required`、未知ソート列 400、無いデータ 404、上流不正 502。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: routes/api.rb:192-227、lib/services/target_genes_tsv.rb:66-67、各 `curl` 結果
- **確認方法**: `curl+ソース確認済み`

---

## 要ブラウザ確認リスト

1. **TG-09**: 設定ページ初期状態で list box 先頭行がハイライトされたまま「View Potential Target Genes」を押すと alert「Select a genome and antigen first.」になること。入力欄に antigen 名を完全に打っても Enter/クリックなしでは同 alert になること。
2. **TG-08**: 入力欄フォーカスで開く 50 件ドロップダウン (`z-index:1050`) が直下の list box に重なる見え方と、blur 後 100 ms で閉じる挙動。
3. **TG-07**: Tutorial ボタンの位置 (h1 と同じ高さ、右端) が本番と一致するか。
4. **TG-14**: 旧 Download (TSV) で `.tsv` をブラウザがダウンロードするか表示するか (Chrome/Firefox/Safari)、保存ファイル名。
5. **TG-15**: 新 Download (TSV) でデータ無し antigen を選ぶと生 JSON が表示されること (ce11 / wdr-5 で再現可)。
6. **TG-25/26**: セル数値の可読性 (青地に白、黄地に黒など)、凡例の見た目。
7. **TG-27**: 「Show experiment columns (131)」展開時の横スクロール (`contain: layout paint`)、モバイル幅 (390 px) でナビバーがはみ出さないこと。hg38/CTCF (2,209 列、0 行) を展開したときの描画時間。
8. **TG-29/30**: ソート矢印の表示、距離切替後のフォールバック注記 (実験列でソート → 距離変更で再現)。
9. **TG-31**: 検索欄の 300 ms デバウンスと 0 件文言、`maxlength=200` の挙動。
10. **TG-40**: 100 行 × 134 列展開時のブラウザ描画時間と、旧 8.8 MB ページの読み込み時間の体感比較。
11. **TG-41**: スクリーンリーダで `aria-sort` / 隠しテキストが読まれるか。
12. 旧設定ページで `<select class="flexselect">` が本当に素の list box として見えているか (JS 初期化が無いことはソースで確認済みだが、視覚確認は未実施)。
13. **TG-04**: 本番で hg38 / CTCF を View したとき、見出しだけの空ページが表示されること。

## 未確認・不確実事項

- Bloodhound (旧 typeahead) の一致方式を「トークン前方一致」と書いたのはライブラリ既定からの推定で、`typeahead.bundle.js` を実行して確かめてはいない。
- hg38 でヘッダのみの TSV がどれだけあるかは CTCF (3 距離) と AATF (3 行) を見ただけで網羅していない。STAT3 は正常 (14,079 行)。他ゲノムの同様事例も未調査。
- 新 index の並び順は DB 挿入順で保証がない (TG-02)。現在一致しているのは上流ファイルが整列済みのため。
- 旧 `/target_genes_result?base=` が外部から使われていたかは不明 (旧 JS からの呼び出しは無い)。
- 旧 `Content-Disposition` 無しの `.tsv` に対するブラウザ挙動は未確認 (要ブラウザ確認 4)。
- 色の一致は Rpl22 (577.95) と末尾行の 2 点のスポットチェックのみ。旧の生成式は不明で、線形補間との差は ±1 程度と推定。
- 旧の列ソート先ページ (`SRX361677.1.html`, `STRING_Stat3.1.html`) は存在と「Sort key」表記を確認したが、行集合が同じ 1,000 行かは未確認。
- 計測値 (cold 1.1 s、warm 6 ms、ダウンロード 0.53 s) はローカル docker から chip-atlas.dbcls.jp への経路で測ったもので、本番配置の値ではない。
- `TargetGenesTsv` のキャッシュ (TTL 5 分、150 MB 上限、FIFO) は同時アクセス時の挙動 (スレッド安全性なしとコメントあり) を試していない。利用者には cold 読み込みの繰り返しとして見える可能性がある。
- 「Show experiment columns (N)」の N は `columns.length - 3` で、Average と STRING が必ず 1 列ずつある前提 (ソース推定)。STRING 列を欠く TSV があれば 1 ずれる。
- 新結果ページの `distance` に「1/5/10」以外を与えたときの挙動は API 404 まで確認したが、距離ボタンがどれも非 active になる見た目は未確認。
- 本番 (chip-atlas.org) の HTML/JS が old-app と同一である点は BRIEF の記述に依拠し、今回は `/target_genes` の HTML だけ照合した。
