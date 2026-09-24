# UI 比較: Colocalization (Colo) — セットアップページ / 結果ページ / ダウンロード

担当接頭辞: `COLO`。調査日 2026-09-23。旧 = https://chip-atlas.org/colo (+ 結果は https://chip-atlas.dbcls.jp/data/<genome>/colo/*.html)、新 = http://localhost:9292/colo, /colo_result。

## 担当範囲の要約

- 新版の `/colo` ピッカーは commit 71cc650 で再有効化済み。`COLO_PICKER_UNAVAILABLE` 定数と "temporarily unavailable" 通知は `frontend/pages/colo.ts` / `views/colo.erb` から削除され、配信中の `/js/colo.js` は `public/js/colo.js` と md5 一致 (457bccf3…)、ゲート文字列は含まれない (curl 確認)。
- index データ: 6 ゲノム (hg38/mm10/rn6/dm6/ce11/sacCer3) すべてで、旧 `/data/colo_analysis.json` と新 `/api/colo_index` の antigen 集合・cell type リスト・順序は **旧の `-` (colo データ無しマーカー) エントリを除いて完全一致** (差分 0 件)。新は `-` を除去しており改良 (COLO-02)。
- 結果データ: hg38 STAT3×Blood について本番 HTML の 1,000 行と新 `/api/colo` の先頭 1,000 行は **行順・Average 値・concordance 色 (16 列×1,000 行) が完全一致**。STRING 色のみ 150 行で 1 チャネル ±1 の差 (丸め方式の違い、視認不可)。本番 HTML は上位 1,000 行のみ、新版は全 3,862 行を表示。
- 退行 (要修正) 2 件: (1) 新ピッカーの list box は先頭行がハイライト表示されるが内部状態は未選択のため、そのまま "View Colocalization Data" を押すと `alert('Select a primary and secondary type first.')` になる (旧は先頭が実選択され即遷移) — COLO-04。(2) "Cell Type Class" のリストがアルファベット順でない (旧は JS で `sort()`) — COLO-03。
- 機能削除 4 件: パートナー行の "↻" ピボットリンク、STRING (string-db.org) リンク、結果ページの "Links: Movie / Document"、旧 `/colo_result?base=` 互換。
- 大きな設計変更 (意図的): 結果は外部静的 HTML からアプリ内描画へ (ナビバー付き、クライアント側ソート、全行表示、ローディング/エラー状態あり)。ただし参照実験 16 列が既定で折りたたまれ、旧版で主表示だったマトリクスが一段階隠れる (COLO-19)。
- 分類集計: 改良 8 / 単なる変更 17 / 機能削除 4 / 退行 (要修正) 2 / データ差分 1 / 新機能 1 (計 33 件)。

### 差分なしと確認した項目 (記録のため)
- 見出し "ChIP-Atlas: Colocalization" + mountain アイコン、Tutorial の 3 リンク (PDF / Movie / Movie (統合TV, Japanese)) と URL (old-app/views/colo.haml:31-49 / views/colo.erb:8-16)。
- "1. Search mode" のラジオ文言 "Antigens → Cell Type" / "Cell Type → Antigen"、既定は前者 (colo.haml:71-81 / colo.erb:25-35)。
- パネル見出しの動的書換え "2. Choose Antigen"/"3. Choose Cell Type Class" ⇄ "2. Choose Cell Type Class"/"3. Choose Antigen" (colo.js:69-80 / colo.ts:68-78)、初期表示は両者とも "2. Choose Primary Type"/"3. Choose Secondary Type" (JS 実行後に書換え)。
- placeholder "type to search"、list box の行数 8 (colo.haml:88-90,98-100 / list-box.ts:34)。
- ボタン文言 "View Colocalization Data" / "Download (TSV)" / "Download (GML)"、3 パネル col-md-3、ボタン col-md-6 offset-3 と col-md-3 ×2。
- ⓘ ヘルプ: 旧新とも Colo ページには存在しない。
- 括弧付き antigen (dm6 の E(z), Su(H) など 15 件): 新は `E%28z%29` にエンコードして data server へ (200)、`/api/colo?genome=dm6&track=E(z)&cell_type=Embryo` → 626 行。空白付き cell type ("Digestive tract") は両者とも `_` 置換 (old-app/lib/pj/location.rb:72 / lib/services/location_service.rb:68-70)、`/api/colo` → 1,807 行。
- TSV/GML のバイト数: 新プロキシ経由と data server 直取得で一致 (263,015 B / 33,228,517 B)。
- 凡例の色コード: ChIP-seq 8 色 (#ff0000 #aaff00 #00ff38 #00ffaa #00e2ff #0071ff #808080 #000000) と STRING 5 段階 + N.D. が同一。

---

## セットアップページ (/colo)

### COLO-01 ゲノムタブが 10 → 6
- **ページ/機能**: Colo > ゲノムタブ
- **旧 (chip-atlas.org)**: H. sapiens (hg38), H. sapiens (hg19), M. musculus (mm10), M. musculus (mm9), R. norvegicus (rn6), D. melanogaster (dm6), D. melanogaster (dm3), C. elegans (ce11), C. elegans (ce10), S. cerevisiae (sacCer3) の 10 タブ (全ゲノム共通の `settings.list_of_genome`)。
- **新 (localhost:9292)**: hg38, mm10, rn6, dm6, ce11, sacCer3 の 6 タブ。TAIR12 は colo データを持つ行が無いため非表示 (`genomes_with_colo` が cell_list ≠ "-" のゲノムだけを返す)。`/api/colo_index?genome=TAIR12` は `{"TAIR12":{"track":{},"cell_type":{}}}`。
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:274-278, colo-old.html 可視テキスト / 新: routes/pages.rb:56-60, lib/models/analysis.rb:57-63, colo-new.html の `#page-data` JSON, curl /api/colo_index?genome=TAIR12
- **確認方法**: `curl+ソース確認済み`
- **備考**: hg19/mm9/dm3/ce10 の削除は BRIEF の意図的変更。TAIR12 が出ないのは index 上の事実 (77 行すべて "-") に基づく導出で妥当。

### COLO-02 index から "-" (colo データ無し) エントリを除去
- **ページ/機能**: Colo > 2./3. パネルの選択肢
- **旧 (chip-atlas.org)**: `/data/colo_analysis.json` は cell_list が "-" の antigen をそのまま含む。hg38: antigen 1,767 件のうち 114 件が `["-"]`、cellline 側にも `"-"` キー (114 antigen) が存在し、"Cell Type → Antigen" モードの Cell Type Class リストに **"-" が 1 項目として表示**される (colo.js は無加工で option 化)。mm10 105 件、rn6 1 件、dm6 8 件、ce11 1 件、sacCer3 25 件。"-" を選んで View すると `https://chip-atlas.dbcls.jp/data/hg38/colo/ADAR.-.html` へ遷移し data server の 404 (nginx) ページになる (HEAD で 404 確認)。
- **新 (localhost:9292)**: `colo_result_by_genome` が `cell_list == "-"` の行を除外。hg38 1,653 antigen / 20 cell type、mm10 768/22、rn6 66/11、dm6 255/5、ce11 161/3、sacCer3 42/1。"-" を除いた antigen 集合・各 antigen の cell type リスト・各 cell type の antigen リストと順序は 6 ゲノムすべてで旧と一致 (差分 0)。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/lib/pj/analysis.rb:33-51, old-app/public/js/pj/colo.js:89-125 / 新: lib/models/analysis.rb:43,76-92, test/routes/api_test.rb:485-489, 6 ゲノムの JSON 比較 (python)
- **確認方法**: `curl+ソース確認済み`

### COLO-03 Cell Type Class のリストがアルファベット順でない
- **ページ/機能**: Colo > "Choose Cell Type Class" パネル (Cell Type → Antigen モードの 2. パネル、および Antigens → Cell Type モードで antigen 未選択時の 3. パネル)
- **旧 (chip-atlas.org)**: `appendOptions` が `options.sort()` してから option を追加するため、antigen / cell type いずれのリストも常にアルファベット順 (hg38: Adipocyte, Blood, Bone, Breast, …)。
- **新 (localhost:9292)**: `primaryItemsFor` / `secondaryItemsFor` は `Object.keys(entry.cell_type)` をそのまま返し、TS 側・Autocomplete 側ともにソートしない。API の `cell_type` キー順は初出順で、hg38 は Others, Prostate, Neural, Breast, Liver, Blood, Digestive tract, Kidney, Pluripotent stem cell, Epidermis, Lung, Uterus, Bone, Cardiovascular, Gonad, Muscle, Placenta, Adipocyte, Pancreas, Embryo。mm10 (Cardiovascular, Neural, Embryonic fibroblast, Blood, …)、rn6、dm6 (Cell line, Embryo, Adult, Larvae, Pupae)、ce11 (Larvae, Adult, Embryo) も非ソート。antigen リスト、antigen→cell type リスト、cell type→antigen リストはデータ側でソート済みのため影響なし (全ゲノムで検証)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/colo.js:107-125 / 新: frontend/pages/colo.ts:35-58, frontend/components/autocomplete.ts:55-76, /api/colo_index の JSON キー順 (python 検証)
- **確認方法**: `curl+ソース確認済み` (表示順の実物は要ブラウザ確認)
- **備考**: `colo_result_by_genome` で `result[genome][:cell_type]` をキー順にソートするか、`primaryItemsFor`/`secondaryItemsFor` で `.sort()` するかの 1 行修正。

### COLO-04 list box の先頭行ハイライトと内部状態の不一致 (View/Download で alert)
- **ページ/機能**: Colo > 2./3. パネル → "View Colocalization Data" / "Download (TSV)" / "Download (GML)"
- **旧 (chip-atlas.org)**: `appendOptions` が先頭 option に `selected` を付けるため、ページ表示直後から primary = 先頭 antigen (hg38: AATF)、secondary = その antigen の先頭 cell type (Others) が **実際に選択済み**。antigen を選ぶと secondary は再生成され先頭が自動選択される。よって「antigen を選ぶ → View」だけで結果に遷移する。typeahead に完全一致文字列を入力しただけでも `keyup` ハンドラが select に反映する (colo.js:151-159)。
- **新 (localhost:9292)**: `ListBox.setOptions` が `options[0].selected = true` にして先頭行を **視覚的に** ハイライトするが `change` イベントは発火せず、`currentPrimary`/`currentSecondary` は `''` のまま。`buildLinkParams()` が null を返し、`alert('Select a primary and secondary type first.')` で止まる。antigen を選択した後も secondary は先頭 (例: STAT3 → Blood) がハイライトされたまま未選択扱いで、ユーザは明示的にクリックする必要がある。typeahead に完全一致を入力しただけ (Enter / 候補クリック / list box クリックなし) では選択にならない。
- **分類**: `退行 (要修正)`
- **影響度**: 高
- **根拠**: 旧: old-app/public/js/pj/colo.js:107-125, 151-159 / 新: frontend/components/list-box.ts:62-69 (`change` は 35-37 のみ), frontend/components/autocomplete.ts:174-188, 200-206, frontend/pages/colo.ts:12-14, 90-96, 125-136, 165-183
- **確認方法**: `ソース推定` (要ブラウザ確認: 実機で alert が出ること)
- **備考**: 見た目 (ハイライト) と挙動 (未選択) が食い違うのが問題。修正案: `Autocomplete.setItems` 後に list box の実選択値を `onSelect` 相当で state に反映する、または ListBox が先頭を自動選択しないようにしてハイライトを出さない。

### COLO-05 secondary パネルの初期内容と選択クリア
- **ページ/機能**: Colo > 3. パネル
- **旧 (chip-atlas.org)**: secondary は常に primary の現在値に従属 (初期は先頭 antigen の cell type のみ、hg38 なら Others 1 件)。
- **新 (localhost:9292)**: antigen 未選択時は「そのゲノムの全 cell type class」を表示 (コメント "shows the range on offer")。primary を選ぶと secondary の入力・選択がクリアされ、その antigen の cell type だけに絞られる。先に secondary を選んでから primary を選ぶと secondary の選択が消える。index に無い primary (ゲノム切替直後) も全件にフォールバック。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo.js:36-41, 99-103 / 新: frontend/pages/colo.ts:40-58, 125-133, frontend/pages/colo.test.ts:60-73
- **確認方法**: `curl+ソース確認済み`

### COLO-06 typeahead の一致方式・候補数・ハイライト
- **ページ/機能**: Colo > 2./3. パネルの入力欄
- **旧 (chip-atlas.org)**: typeahead.js + Bloodhound (whitespace tokenizer = 語頭一致)、`minLength: 1`、候補 15 件、hint と一致部分ハイライトあり (colo.js:131-149)。下の select は絞り込まれない。
- **新 (localhost:9292)**: 大文字小文字無視の部分一致 (`includes`)、候補最大 50 件、一致部分のハイライトなし、キーボード操作 (↑↓ Enter Esc)、`role=combobox`/`aria-activedescendant` 付与。入力中は下の list box も同じ条件で絞り込まれる (空クエリは全件、非空クエリは **最大 50 件で打ち切り**)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: colo.js:127-160 / 新: frontend/components/autocomplete.ts:24, 55-76, 78-110, 120-125, 139-162
- **確認方法**: `curl+ソース確認済み`
- **備考**: 部分一致 (例 "TAT3" → STAT3) は改良。list box の 50 件打ち切りは "S" のような短い入力で antigen 一覧が途中で切れるため、備考として記録 (要ブラウザ確認)。

### COLO-07 リード文の句点と meta description
- **ページ/機能**: Colo > ヘッダ
- **旧 (chip-atlas.org)**: リード "Predict potential partner proteins that form complexes with given TFs" (句点なし)。`<meta name="description">` は "Prediction of colocalization pertners of transcription factors." (pertners の綴り誤り)。
- **新 (localhost:9292)**: リード "Predict potential partner proteins that form complexes with given TFs." (句点あり)。meta description は同文。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/colo.haml:8, 34-35 / 新: views/colo.erb:3, 10
- **確認方法**: `curl+ソース確認済み`

### COLO-08 Tutorial ドロップダウンの実装差
- **ページ/機能**: Colo > Tutorial ボタン
- **旧 (chip-atlas.org)**: Bootstrap 3 dropdown、`<div class="button btn btn-primary dropdown-toggle">` + caret、メニューは左寄せ。
- **新 (localhost:9292)**: `<button>` + Bootstrap 5 `dropdown-menu-end` (右寄せ)、各リンクに `rel="noopener noreferrer"`。文言・URL は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo.haml:36-49 / 新: views/_page_header.erb:24-28, views/_tutorial.erb:7-26
- **確認方法**: `curl+ソース確認済み` (見た目は要ブラウザ確認)

### COLO-09 ボタンのサイズと余白
- **ページ/機能**: Colo > View / Download ボタン
- **旧 (chip-atlas.org)**: 3 ボタンとも `btn-lg btn-block`。View は `.button-submit.down` (margin-top 5em) + button margin-top 2em、Download 行は `.row.colo-download` margin-top 2em。
- **新 (localhost:9292)**: View は `btn-lg`、Download 2 つは通常サイズ (`btn btn-primary btn-block`、BS5 では `d-grid` で幅いっぱい)。余白は `mb-2` / `mb-4`。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo.haml:102-112, old-app/views/style.sass:94-100, 131-134 / 新: views/colo.erb:58-71
- **確認方法**: `ソース推定` (要ブラウザ確認)

### COLO-10 "View Colocalization Data" の遷移先: 外部静的 HTML → アプリ内ページ
- **ページ/機能**: Colo > View Colocalization Data
- **旧 (chip-atlas.org)**: クリックでボタンを disabled にし `POST /colo?type=submit` (JSON `{condition:{genome,antigen,cellline}}`) → `{"url": "https://chip-atlas.dbcls.jp/data/hg38/colo/STAT3.Blood.html"}` → `window.open(url, "_self")` で **サイト外の静的 HTML** (ナビバー/フッター無し、`<FONT face="Helvetica Neue">`) に同タブ遷移。POST 失敗時は `alert("error!")` → `/not_found`。
- **新 (localhost:9292)**: `GET /colo_result?genome=hg38&track=STAT3&cell_type=Blood` にアプリ内遷移 (ナビバー "Colo" が active、フッターあり)。データは `/api/colo` から取得しクライアント描画。POST は無い。
- **分類**: `改良`
- **影響度**: 高
- **根拠**: 旧: colo.js:163-236, old-app/app.rb:280-286, old-app/lib/pj/location.rb:70-82 / 新: frontend/pages/colo.ts:90-96, 165-169, routes/pages.rb:62-65, routes/api.rb:158-171, colo_result-new.html (nav-link active href="/colo")
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新版は URL が (genome, track, cell_type) の deep link になり共有可能。

### COLO-11 ダウンロードが attachment 配信に
- **ページ/機能**: Colo > Download (TSV) / Download (GML)、結果ページの Download TSV / GML
- **旧 (chip-atlas.org)**: `POST /colo?type=tsv|gml` → data server の URL (`…/STAT3.Blood.tsv`, `…/Blood.gml`) を同タブで開く。data server は `Content-Disposition` を付けず、TSV は `text/tab-separated-values`、GML は `application/gml+xml`。インライン表示になるかダウンロードになるかはブラウザ依存。結果ページ内の "Downloads: TSV (text), GML (Cytoscape)" リンクは `target="_blank"`。
- **新 (localhost:9292)**: `GET /api/colo/download?genome=…&track=…&cell_type=…&format=tsv|gml` が data server から取得して `Content-Disposition: attachment; filename="STAT3.Blood.tsv"` / `"STAT3.Blood.gml"` で返す (TSV: `text/tab-separated-values;charset=utf-8`、GML: `application/xml;charset=utf-8`)。format 不正は 400 `{"error":"Unknown format: xxx. Available: tsv, gml"}`、パラメータ欠落は 400、上流 404 は 404 `{"error":"File not found"}`。バイト数は直取得と一致。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: colo.js:170-191, location.rb:70-82, `curl -I https://chip-atlas.dbcls.jp/data/hg38/colo/STAT3.Blood.tsv` (Content-Disposition 無し) / 新: routes/api.rb:173-185, frontend/pages/colo.ts:171-183, frontend/pages/colo-result.ts:533-541, curl -D の応答ヘッダ
- **確認方法**: `curl+ソース確認済み` (旧のクリック時挙動は要ブラウザ確認)

### COLO-12 GML の保存ファイル名に antigen 名が付く
- **ページ/機能**: Colo > Download (GML)
- **旧 (chip-atlas.org)**: 実ファイルは cell type 単位の `Blood.gml` (antigen に依らず同一ファイル、33 MB)。
- **新 (localhost:9292)**: attachment ファイル名が `STAT3.Blood.gml` (`"#{track}.#{cell_type}.#{format}"` を TSV/GML 共通で組み立て)。同じ Blood.gml を STAT1 で落とすと `STAT1.Blood.gml` になり、別内容と誤解され得る。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: location.rb:79-80, `curl -I …/Blood.gml` / 新: routes/api.rb:183, curl -D (`filename="STAT3.Blood.gml"`)
- **確認方法**: `curl+ソース確認済み`
- **備考**: GML は `"#{cell_type}.gml"` にするのが実体に即す。

### COLO-13 ダウンロードが Ruby プロキシ経由 (全量バッファ)
- **ページ/機能**: Colo > Download (GML) (33 MB) / Download (TSV) (263 KB)
- **旧 (chip-atlas.org)**: ブラウザが data server から直接取得 (first byte 0.05 s)。
- **新 (localhost:9292)**: `DataProxy.fetch` が `Net::HTTP#get` で本文全体をメモリに読み込んでから返すため、GML では first byte まで 1.17 s (合計 1.19 s、直取得は 1.39 s)。ダウンロード開始まで無反応に見える時間が増える。open/read timeout は 10 s / 30 s。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 新: lib/services/data_proxy.rb:55-69, routes/api.rb:181-185, `curl -w` 計測 (1 回ずつ)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 大きいファイルはリダイレクトかストリーミングが望ましい。

### COLO-14 URL ハッシュでゲノムタブを保持
- **ページ/機能**: Colo > ゲノムタブ
- **旧 (chip-atlas.org)**: タブ状態は URL に残らない。
- **新 (localhost:9292)**: タブ選択で `#genome=mm10` を `history.replaceState`、再読み込み/共有時に復元。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 新: frontend/components/genome-tabs.ts:8-30, 68, 79-82
- **確認方法**: `ソース推定`

### COLO-15 ゲノム切替時の状態保持と index の再取得
- **ページ/機能**: Colo > ゲノムタブ切替
- **旧 (chip-atlas.org)**: ゲノムごとに独立したパネル一式 (10 組) を持ち、タブを戻すと選択・ラジオ状態が残る。ただし `shown.bs.tab` のたびに `/data/colo_analysis.json` を再取得し、`change` ハンドラを再登録する (多重登録)。
- **新 (localhost:9292)**: 単一のパネル一式。切替時に primary/secondary をクリア (ラジオは維持)、index はゲノムごとにキャッシュして再取得しない。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo.haml:56-112, colo.js:12-34, 43-59 / 新: frontend/pages/colo.ts:80-88, 151-161
- **確認方法**: `curl+ソース確認済み`

### COLO-16 index 取得失敗時の通知
- **ページ/機能**: Colo > 2./3. パネル
- **旧 (chip-atlas.org)**: `$.ajax` に error ハンドラ無し。パネルは空のまま、通知なし。
- **新 (localhost:9292)**: `console.warn` のみ。パネルは空のまま、ユーザ向けメッセージなし。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo.js:20-34 / 新: frontend/pages/colo.ts:80-88
- **確認方法**: `ソース推定`

## 結果ページ (/colo_result ⇔ 旧 外部 HTML)

### COLO-17 見出し・タイトル・ジョブ情報ブロックの文言
- **ページ/機能**: Colo 結果 > ヘッダ
- **旧 (chip-atlas.org)**: `<title>ChIP-Atlas | Colocalization</title>`、`<h1>ChIP-Atlas: Colocalization analysis</h1>`、`<h2>Colocalization analysis for STAT3</h2>`、"Query protein: STAT3" / "Cell class: Blood" / "Sort key: STAT3 | Average" の 3 行。ゲノム名の表示なし。
- **新 (localhost:9292)**: `<title>ChIP-Atlas: Colocalization Result</title>`、`<h1>ChIP-Atlas: Colocalization Result</h1>`、要約 1 行 "STAT3 (Blood) on hg38" (text-muted small)。"Sort key" 文言は無く、ソート列はヘッダの ↓/↑ と `aria-sort` で示す。meta description "Predicted colocalization partners and their peak-intensity concordance."。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:3, 31-37 / 新: views/colo_result.erb:2-9, frontend/pages/colo-result.ts:543-545
- **確認方法**: `curl+ソース確認済み`
- **備考**: commit ca0aa42 の "job info" は Enrichment/Diff の結果ページのみで、Colo には該当ブロック無し (git show --stat で確認)。ゲノム名が明示されるのは改良。

### COLO-18 表示行数: 上位 1,000 行 → 全 3,862 行
- **ページ/機能**: Colo 結果 > 表
- **旧 (chip-atlas.org)**: 静的 HTML は `mainTable` に header + 1,000 行のみ (TSV は 3,862 行)。行数表示なし。
- **新 (localhost:9292)**: `/api/colo` が TSV 全行 (3,862 行 × 21 列、407 KB JSON) を返し、全行を一度に描画。末尾に "3,862 colocalization partners" (0 件なら "No colocalization partners found")。先頭 1,000 行の順序と Average 値は本番と完全一致。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: colo-result-old-STAT3.Blood.html (tr 1,001 本), TSV 263,015 B / 新: lib/services/colo_tsv.rb:100-109, frontend/pages/colo-result.ts:517-519, python 比較
- **確認方法**: `curl+ソース確認済み` (描画時間は要ブラウザ確認)
- **備考**: ledger には 1440px で 89,079 DOM ノード、DOMContentLoaded 33 ms と記録あり (docs/superpowers/plans/2026-09-18-post-parity-fixes-ledger.md:388-390)。3,862 行のうち 3,259 行は Average 0 (concordance なし) で、"partners" の語は緩い。

### COLO-19 参照実験 (SRX) 列が既定で折りたたみ
- **ページ/機能**: Colo 結果 > 表の SRX 列
- **旧 (chip-atlas.org)**: 参照実験 16 列 (STAT3 の Blood 実験ごとの concordance 色) を常時表示。マトリクスそのものが主表示。
- **新 (localhost:9292)**: `<details>` "Show reference-experiment columns (16)" を開くまで `.tg-exp-col { display: none }`。開くと "Hide reference-experiment columns (16)" に変わる。説明文 "Individual reference experiments are summarized by the query antigen's Average column above. Expanding adds one column per reference experiment, already loaded with this result — no extra request is made."。既定では Experiment / Cell type / Protein / Average / STRING の 5 列のみ。
- **分類**: `単なる変更`
- **影響度**: 高
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:69-93 / 新: views/colo_result.erb:56-63, frontend/pages/colo-result.ts:403-408, 522-531, 575-582, public/css/style.css:628-634
- **確認方法**: `curl+ソース確認済み` (開閉は要ブラウザ確認)
- **備考**: Target Genes と同じ折りたたみイディオムで、ledger に "column-axis decision" として意図的と記録 (ledger:290, 392)。ただし Colo は列数が 16 程度で横スクロールの必然性が薄く、旧版ユーザにはマトリクスが消えたように見える。既定で展開する、または列数が閾値未満なら展開する案を提案。

### COLO-20 セルにラベル・数値を表示 (旧は色のみ)
- **ページ/機能**: Colo 結果 > セル
- **旧 (chip-atlas.org)**: 全セルは `bgcolor` のみで文字なし。末尾の inline script が SRX 列のセルに `title = "<cell type>\n(<SRX>)\n\n<partner protein>"` を付与 (Average/STRING 列には無し)。
- **新 (localhost:9292)**: SRX 列は色 + ラベル ("H-H" "H-M" "M-M" "H-L" "M-L" "L-L" "N.D." "Same"、想定外値は "?")、`title="raw concordance score: 9"`。Average は色 + 数値 (整数以外は小数 2 桁、例 3.87)、`title="Average concordance (0-9 scale) shown on the STRING color scale above"`。STRING は色 + 数値 (908)。文字色は輝度で黒/白を自動選択。"Same" (値 10) は行の SRX と列ヘッダの SRX が一致する時のみ黒。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:94-118 および末尾 script / 新: frontend/pages/colo-result.ts:131-158, 195-198, 272-274, 424-454
- **確認方法**: `curl+ソース確認済み`
- **備考**: 色だけに依存しない表示になった。旧 tooltip の "cell type / SRX / protein" 情報は列ヘッダ ("SRX150636: GM12878") と行に分散。

### COLO-21 列構成と見出し文言
- **ページ/機能**: Colo 結果 > 表ヘッダ
- **旧 (chip-atlas.org)**: "Cell types" | "Exp. IDs" | "**STAT3**'s Colocalization partners" | (↻ 列、見出しなし) | "STAT3: Average" (回転 -45°) | (空白列) | "SRX17215538: Anaplastic large cell lymphoma" … ×16 (回転) | (空白列) | "STAT3: STRING"。
- **新 (localhost:9292)**: "Experiment" | "Cell type" | "Protein" | "Average" (title "STAT3 | Average") | "SRX17215538: Anaplastic_large_cell_lymphoma" … ×16 (折りたたみ、各列に ↗ /view リンク) | "STRING"。Experiment が先頭、antigen 名が見出しから消え、回転表示なし。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:69-93 / 新: frontend/pages/colo-result.ts:372-422
- **確認方法**: `curl+ソース確認済み`

### COLO-22 ソート: 別ページ遷移 → クライアント側トグル
- **ページ/機能**: Colo 結果 > 列ソート
- **旧 (chip-atlas.org)**: 各列ヘッダの "◢" (title "Sort by this column...") は **別の事前計算 HTML** へのリンク: Average → 同ページ、SRX 列 → `<SRX>.html` ("Sort key: SRX347427 | SU-DHL-4")、STRING → `STRING_STAT3.Blood.html` ("Sort key: STAT3 | STRING")。降順のみ、ページ再読み込み、Cell types / Exp. IDs / partners 列はソート不可。
- **新 (localhost:9292)**: 全列がボタン化されクリックで降順→昇順トグル、再読み込みなし、`aria-sort` と視覚的矢印、キーボード操作可。既定は Average 降順 (サーバ側で `sort_by { -avg }` 済み)。文字列列は `localeCompare`。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:74-93, `curl -r` で SRX347427.html / STRING_STAT3.Blood.html の Sort key 確認 / 新: frontend/pages/colo-result.ts:285-370, 505-520, lib/services/colo_tsv.rb:104-108
- **確認方法**: `curl+ソース確認済み` (再描画速度は要ブラウザ確認)
- **備考**: Ruby の `sort_by` は安定ソートでないが、同値 (Average) の並びは先頭 1,000 行で本番と一致した。

### COLO-23 パートナー行の "↻" ピボットリンクが無い
- **ページ/機能**: Colo 結果 > 各行 4 列目
- **旧 (chip-atlas.org)**: 各行に `<a title="Serach this partner..." href="https://chip-atlas.dbcls.jp/data/hg38/colo/<SRX>.html">↻</a>`。遷移先は **そのパートナー実験自身を起点にした colo 解析** (例 SRX212647.html: "Colocalization analysis for STAT1 / Cell class: Blood / Sort key: SRX212647 | Monocytes-CD14+")。パートナーを辿って解析を連鎖できる。
- **新 (localhost:9292)**: 該当リンクなし。`/colo_result` は (genome, track, cell_type) のみを受け、SRX 単位の解析ページ (`<SRX>.html` / `<SRX>.tsv`) に相当する API は無い。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:97, `curl -r` SRX212647.html の見出し / 新: frontend/pages/colo-result.ts:456-500 (リンクは Experiment → /view のみ), routes/api.rb:158-171
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的かどうか docs に記述なし (推定: 未移植)。最低限、行の Protein/Cell type から `/colo_result?genome=&track=<Protein>&cell_type=<same class>` へのリンクで近い導線は作れる (ただし旧は SRX 列でソート済みの表)。

### COLO-24 STRING (string-db.org) リンクが無い
- **ページ/機能**: Colo 結果 > STRING 列
- **旧 (chip-atlas.org)**: ヘッダ "STAT3" → `http://string-db.org/newstring_cgi/show_network_section.pl?identifier=9606.ENSP00000264657` (title "Serach STAT3 in STRING.")、各行の STRING セルに "≫" → 2 タンパク質ネットワーク (`identifiers=9606.ENSP…%250D9606.ENSP…`、title "Serach STAT3 and STAT1 in STRING.")。
- **新 (localhost:9292)**: 数値と色のみ、リンクなし。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:93, 117 / 新: frontend/pages/colo-result.ts:435-443
- **確認方法**: `curl+ソース確認済み`
- **備考**: TSV には ENSP ID が含まれないため、再現には別データ (旧 HTML 生成側が持つ ENSP 対応表) が必要 (推定)。

### COLO-25 /view リンクの開き方
- **ページ/機能**: Colo 結果 > Exp. IDs / SRX 列ヘッダ
- **旧 (chip-atlas.org)**: `http://chip-atlas.org/view?id=SRX…` を `target="_blank"` で新規タブ (title "Open this Info..." / "Open info to SRX…")。
- **新 (localhost:9292)**: 相対 `/view?id=SRX…` を同タブ。SRX 列ヘッダは "↗" (aria-label "View experiment SRX…")。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:74-96 / 新: frontend/pages/colo-result.ts:411-416, 466-473
- **確認方法**: `curl+ソース確認済み`

### COLO-26 "Links: Movie / Document" ブロックが無い
- **ページ/機能**: Colo 結果 > Downloads/Links 行
- **旧 (chip-atlas.org)**: "Downloads: TSV (text), GML (Cytoscape)" の下に "Links: Movie (https://youtu.be/kM9YkPOfsyY) and Document (https://github.com/inutano/chip-atlas/wiki#6-colocalization) for ChIP-Atlas Colocalization" (それぞれ chip-atlas.org / chip-atlas.org/colo へのリンク)。
- **新 (localhost:9292)**: "Download TSV" / "Download GML" ボタンのみ。"(text)" "(Cytoscape)" の補足も無し。Movie/Document へのリンクは結果ページに無い (セットアップページの Tutorial にはある)。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:66-67 / 新: views/colo_result.erb:11-18
- **確認方法**: `curl+ソース確認済み`

### COLO-27 凡例の文言・順序・Average の説明
- **ページ/機能**: Colo 結果 > Color legends
- **旧 (chip-atlas.org)**: "Color legends" / "ChIP-seq data: H-H H-M M-M H-L M-L L-L N.D. Same (Peak intensities are **H**igh, **M**iddle or **L**ow)" / "STRING data: 1000 750 500 250 0 N.D. (Values = STRING's binding scores)" (降順)。
- **新 (localhost:9292)**: "Color legend — ChIP-seq data (peak-intensity concordance between the query and each reference experiment)" 同 8 色同順 / "Color legend — STRING data (STRING's binding score)" N.D. 0 250 500 750 1000+ (昇順、"1000+" 表記) / 追加説明 "The Average column above (mean peak-intensity concordance across reference experiments, on a 0–9 scale) is shown on this same color scale."。`role="img"` + aria-label 付き。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo-result-old-STAT3.Blood.html:39-64 / 新: views/colo_result.erb:22-50
- **確認方法**: `curl+ソース確認済み`

### COLO-28 STRING / Average セル色の ±1 チャネル差
- **ページ/機能**: Colo 結果 > STRING 列、Average 列の色
- **旧 (chip-atlas.org)**: 生成側は補間値を切り捨て (例 STRING 908 → `#ff5d00`、464 → `#00ff24`)。
- **新 (localhost:9292)**: `scoreToRgb` は `Math.round` (908 → `#ff5e00`、464 → `#00ff25`)。本番 1,000 行中 150 行 (STRING > 0 の行) で 1 チャネル ±1。Average は `floor` を使い 1 行のみ差 (SRX347426 2.4: 本番 `#00ffee` / 新 `#00ffed`、浮動小数の丸め)。concordance 16 列は完全一致。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 新: frontend/pages/colo-result.ts:165-189 (round), 238-270 (floor) / python 比較 (checked 1,000 行)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 視認不可。`scoreToRgb` も floor にすれば完全一致するが、Target Genes と共有の関数を byte-identical に保つ意図がコメントにある。

### COLO-29 細胞種名のアンダースコアが生表示
- **ページ/機能**: Colo 結果 > Cell type 列、SRX 列ヘッダ
- **旧 (chip-atlas.org)**: TSV の `_` を空白に置換して表示 ("Lymphoblastoid cell line", "Th2 Cells", ヘッダ "Anaplastic large cell lymphoma", "Naive B cells")。
- **新 (localhost:9292)**: TSV の生値 ("Lymphoblastoid_cell_line", "B_cells", "Acute_myeloid_leukemia", ヘッダ "SRX17215538: Anaplastic_large_cell_lymphoma")。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: colo-result-old-STAT3.Blood.html (`Lymphoblastoid&nbsp;cell&nbsp;line` ×9 など、`_` を含む行なし) / 新: frontend/pages/colo-result.ts:406-409, 475-479, /api/colo の rows
- **確認方法**: `curl+ソース確認済み`
- **備考**: 表示時に `_` → 空白の 1 行修正で揃う。

### COLO-30 ローディング表示とエラー状態
- **ページ/機能**: Colo 結果 > 読み込み中 / 存在しない組合せ / パラメータ欠落
- **旧 (chip-atlas.org)**: 静的 HTML のためローディング無し。存在しない組合せ (例 `ADAR.-.html`) は data server の nginx 404 ページ (ChIP-Atlas の体裁なし)。`GET /colo_result` (base 無し) と `?base=<存在しない URL>` は **500 Internal Server Error** (curl 確認)。
- **新 (localhost:9292)**: "Loading…" → 成功で表、失敗で赤い alert "Failed to load colocalization data. This antigen/genome/cell-type combination may not have precomputed data." (Download ボタンは非表示)。パラメータ欠落は "Missing genome, track, or cell_type parameter in URL."。API 側: 400 `genome, track, and cell_type required`、404 `Colocalization data not found`、502 `Colocalization data could not be parsed: …`。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/app.rb:288-295, curl -I chip-atlas.org/colo_result (500), curl -I …/ADAR.-.html (404) / 新: views/colo_result.erb:52-53, frontend/pages/colo-result.ts:547-573, 584-601, routes/api.rb:158-171, curl 応答
- **確認方法**: `curl+ソース確認済み`

### COLO-31 空白付き cell type の attachment ファイル名
- **ページ/機能**: Colo > Download (TSV/GML) で "Digestive tract" 等
- **旧 (chip-atlas.org)**: 実ファイル名 `STAT3.Digestive_tract.tsv` (URL 生成時に `_` 置換)。
- **新 (localhost:9292)**: 取得 URL は同じく `_` 置換だが、attachment ファイル名は `"STAT3.Digestive tract.tsv"` (空白入り)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 新: routes/api.rb:183, curl -D (`filename="STAT3.Digestive tract.tsv"`)
- **確認方法**: `curl+ソース確認済み`

### COLO-32 index API の形状変更
- **ページ/機能**: Colo > index 取得 (ユーザ非可視、API 利用者向け)
- **旧 (chip-atlas.org)**: `GET /data/colo_analysis.json?genome=hg38` → `{"hg38":{"antigen":{…},"cellline":{…}}}`。未知ゲノムは `{"zzz":{}}` (200)。
- **新 (localhost:9292)**: `GET /api/colo_index?genome=hg38` → `{"hg38":{"track":{…},"cell_type":{…}}}` (`Cache-Control: public, max-age=3600`)。未知ゲノムは `{"hg19":{"track":{},"cell_type":{}}}` (200)、genome 欠落は 400 `genome parameter required`。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/app.rb:110-127 / 新: routes/api.rb:115-119, curl 応答
- **確認方法**: `curl+ソース確認済み`
- **備考**: BRIEF の意図的変更 (`/data/*` → `/api/*`、フィールド改名)。

### COLO-33 旧 `/colo_result?base=<URL>` の互換なし
- **ページ/機能**: Colo 結果 > 旧 URL
- **旧 (chip-atlas.org)**: `GET /colo_result?base=<url>` はリモートファイルがあれば `base` へリダイレクト (旧 UI 自体はこの経路を使わず、JS が直接 data server へ遷移)。
- **新 (localhost:9292)**: `base` は無視され "Missing genome, track, or cell_type parameter in URL." を表示。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: old-app/app.rb:288-295 / 新: frontend/pages/colo-result.ts:52-59, 584-592
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧の当該ルートは任意 URL へのオープンリダイレクトであり、廃止は妥当 (セキュリティ側の担当範囲)。

---

## 要ブラウザ確認リスト
1. COLO-04: ページ表示直後および antigen 選択直後に list box の先頭行がハイライトされた状態で "View Colocalization Data" を押すと `alert('Select a primary and secondary type first.')` になること (旧は AATF×Others へ遷移)。
2. COLO-03: "Cell Type → Antigen" を選んだ時の 2. パネルの並び (Others, Prostate, Neural, … の順で出るか)。
3. COLO-06: 入力欄フォーカス時の候補ドロップダウン (absolute, z-index 1050, max-height 320px) が下の list box に重なる見え方、短い入力で list box が 50 件で切れること。
4. COLO-09 / COLO-08: ボタンサイズ・余白・Tutorial メニューの位置の見た目。
5. COLO-18 / COLO-22: 3,862 行 (約 89k DOM ノード) の初期描画とソートクリック時の再描画時間 (低速端末・モバイル幅)。
6. COLO-19: "Show reference-experiment columns (16)" の開閉、開いた時の横スクロール (`#result-table-wrap` の `overflow-x: auto`)。
7. COLO-11: 旧版で Download (TSV) を押した時にブラウザがインライン表示するかダウンロードするか (Content-Disposition 無し)。新版 attachment のファイル名がブラウザでどう表示されるか (空白入り COLO-31 を含む)。
8. COLO-14: `#genome=…` の復元とブラウザ戻る時の挙動 (`replaceState` のため履歴は増えない)。
9. COLO-20: 黒セル "Same" の白文字、Average/STRING セルの文字色 (輝度による自動選択) の可読性。

## 未確認・不確実事項
- COLO-04 は list-box.ts / autocomplete.ts / colo.ts のソース読解に基づく推定で、実機で alert が出ることは未確認 (ただし `change` イベントなしに state が更新される経路はソース上見当たらない)。
- 旧 colo.js のタブ切替ごとの `change` ハンドラ多重登録 (COLO-15) が旧版で実害を生んでいるかは未確認。
- 新版の `log_activity('colo', …)` (routes/api.rb:169) が何を記録するかは未読 (ユーザ非可視のため範囲外とした)。
- COLO-23 / COLO-24 (↻ ピボット、STRING リンク) の削除が意図的かは docs に記述が見当たらず不明。STRING リンク再現に必要な ENSP ID の入手元も未調査。
- TAIR12 に colo データが無いことは index (analysisList.tab 由来、全行 "-") でのみ確認。data server 側に `TAIR12/colo/` が存在しないことは未確認。
- 本番の結果 HTML/TSV は Last-Modified 2025-02-02。新版が同じ data server のファイルを読むため内容は同一だが、将来の再生成で本番 HTML (1,000 行) と TSV (全行) の関係が変わる可能性は考慮していない。
- COLO-13 の計測は各 1 回 (ローカル docker → data server)。ネットワーク状況で変動する。
- 6 ゲノム以外 (hg19/mm9/dm3/ce10) の index は新版に存在しないため比較していない。
- 旧の "-" cell type 選択時の遷移先が nginx 404 であることは HEAD で確認したが、旧 JS の `window.open` 後にブラウザが何を表示するかは実機未確認。
