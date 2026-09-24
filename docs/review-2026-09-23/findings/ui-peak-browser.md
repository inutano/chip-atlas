# Peak Browser 新旧比較 (ID 接頭辞: PB)  — 2026-09-23

## 担当範囲の要約

- 対象: `/peak_browser` ページと、そこから行える操作すべて (ゲノムタブ、5 つのパネル、type-to-search、ⓘ、View on IGV、Download BED file、Tutorial)。
- 方法: 本番 (chip-atlas.org) は GET のみ (`/peak_browser`, `/data/experiment_types|sample_types|chip_antigen|cell_type`, `/qvalue_range`, `/data/list_of_genome.json`, `/js/pj/*.js`)。新版 (localhost:9292) は `/api/*` GET/POST を実行し、`database.sqlite.verify` を `sqlite3 -readonly` で参照。本番の `POST /browse` `/download` は呼ばず、`old-app/lib/pj/location.rb` を読んで URL 生成を再現した。データサーバ (chip-atlas.dbcls.jp) には HEAD のみ 12 回。
- 本番配信 JS と `old-app/public/js/pj/{peak_browser,pj}.js` の SHA-256 一致を再確認済み (fba2d29f… / b732dc0b…)。
- **選択肢リスト (id/label/順序/件数) は hg38・mm10・sacCer3 のトラック種別、hg38 の細胞種別クラス 5 種と mm10 Histone、hg38 の抗原リスト 2 条件、細胞種リスト 2 条件で完全一致**。"Unclassified"・"No description"・"NA" の扱いも同じ。CUT&Tag / CUT&RUN は新旧どちらのメニューにも存在しない。
- 一方で **機能面の退行が 4 件 (影響度 高 3 件)**: (1) Bisulfite-Seq は新版で qval "05" を送るため URL が生成できない (旧版は "bs")、(2) Annotation tracks は qval "anno" が送られず、さらに既定の "All" 選択と `get_trackname` の順序バグで IGV 用 API が 500 を返す、(3) 抗原と細胞種を同時選択できてしまい (旧版は相互排他の警告)、URL が null になる、(4) "Error connecting to IGV?" のリンク先 wiki アンカー `#igv_doc` が存在せず、旧版の port 60151 設定手順が失われた。
- null URL 時の挙動 (`/null` へ遷移し 404) は新旧同じだが、新版では到達しやすくなった。
- 改良点: IGV 起動確認 (到達不能時はページを離れずメッセージ表示)、部分一致検索、双方向の件数更新、選択状態の保持、`#genome=` ディープリンク、キーボード/ARIA 対応、API 失敗時のメッセージ表示。
- 集計: 改良 10 / 単なる変更 8 / 機能削除 1 / 退行 (要修正) 7 / データ差分 1 / 新機能 2 (計 29 項目)。

## 差分なしを確認した事項 (項目化しない)

- ページ `<title>` "ChIP-Atlas: Peak Browser"、meta description、見出し "ChIP-Atlas: Peak Browser" + 山アイコン、Tutorial の 3 リンク URL (PDF / youtu.be/qKNOkK-8hDo / doi.org/10.7875/togotv.2018.023)。
- パネル見出し 5 種の文言、リストボックス行数 (クラス・サブクラス 8 行、閾値 5 行)、単一選択 (どちらも `multiple` なし)、既定選択 (Histone / All cell types / All / All / 50)、"All cell types" 行に件数あり・"All" 行に件数なし、閾値ラベル 50/100/200/500 (値 05/10/20/50)、ⓘ 本文 (文字列比較で完全一致)。
- 生成 URL: hg38 Histone×All → `https://chip-atlas.dbcls.jp/data/hg38/assembled/His.ALL.05.AllAg.AllCell.bed`、H3K4me3×All cell types → `His.ALL.05.H3K4me3.AllCell.bed`、All×Blood/K-562 → `His.Bld.05.AllAg.K-562.bed`、IGV → `http://localhost:60151/load?genome=hg38&file=<上記>`、Annotation (CpG Islands) → `…/data/annotations/hg38/cpg_island.bed.gz` (+`&name=CpG Islands`)。いずれも archive で HEAD 200。
- 推定ファイルサイズ表示: 新旧とも Peak Browser には無い (`number_of_lines` / `/api/bed_sizes` は Enrichment Analysis 専用)。"node status" 表示も新旧とも無い。
- 選択肢の取得失敗 (ネットワークエラー) 時: 新旧ともユーザ向けメッセージ無し (リストが空のまま)。

---

### PB-01 リード文末尾のピリオド
- **ページ/機能**: Peak Browser > ヘッダ
- **旧 (chip-atlas.org)**: "Visualize TF-binding, histone marks, chromatin accessibility, and DNA methylation on IGV" (リンク "IGV" で文が終わり、ピリオド無し)
- **新 (localhost:9292)**: "… on IGV." (ピリオド追加、リンクに `rel="noopener noreferrer"`)
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:36-39 / 新: views/peak_browser.erb:10-11、curl 出力
- **確認方法**: curl+ソース確認済み

### PB-02 見出し下の罫線
- **ページ/機能**: Peak Browser > ヘッダ
- **旧 (chip-atlas.org)**: `div.header` (Bootstrap 3 にも style.sass にも `.header` の定義なし) → 見出し下に罫線は無い
- **新 (localhost:9292)**: `div.page-header` に `border-bottom: 1px solid var(--ca-rule)` → 見出しとタブの間に罫線が出る
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: pb/prod_peak_browser.html:119 `class="header"`、old-app/public/css/bootstrap.min.css に `.header{` 0 件 / 新: views/_page_header.erb:13、public/css/style.css:353-357
- **確認方法**: ソース推定 (要ブラウザ確認)
- **備考**: docs/ui-parity-audit-2026-09-14.md は「本番は .page-header」と書いているが、Peak Browser の本番 HTML は `.header`。

### PB-03 Tutorial ドロップダウンの実装
- **ページ/機能**: Peak Browser > Tutorial
- **旧 (chip-atlas.org)**: `div.button.btn.btn-primary.dropdown-toggle` (div なのでキーボードフォーカス不可) + `span.caret`。メニュー左寄せ
- **新 (localhost:9292)**: `<button class="btn btn-primary dropdown-toggle">` + `ul.dropdown-menu.dropdown-menu-end` (右寄せ)。リンク先は同一、`rel="noopener noreferrer"` 追加
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:42-56 / 新: views/_tutorial.erb:9-24
- **確認方法**: curl+ソース確認済み

### PB-04 ゲノムタブ: 10 → 7 (hg19/mm9/dm3/ce10 削除、TAIR12 追加)
- **ページ/機能**: Peak Browser > ゲノムタブ
- **旧 (chip-atlas.org)**: 順に "H. sapiens (hg38)", "H. sapiens (hg19)", "M. musculus (mm10)", "M. musculus (mm9)", "R. norvegicus (rn6)", "D. melanogaster (dm6)", "D. melanogaster (dm3)", "C. elegans (ce11)", "C. elegans (ce10)", "S. cerevisiae (sacCer3)" (10 タブ、`<a role=tab>`)
- **新 (localhost:9292)**: "H. sapiens (hg38)", "M. musculus (mm10)", "R. norvegicus (rn6)", "D. melanogaster (dm6)", "C. elegans (ce11)", "S. cerevisiae (sacCer3)", "A. thaliana (TAIR12)" (7 タブ、`<button role=tab aria-selected>`)。共通 6 ゲノムのラベル・順序は同一
- **分類**: データ差分
- **影響度**: 高 (hg19/mm9 利用者は旧アセンブリの BED を Peak Browser から得られなくなる)
- **根拠**: 旧: old-app/lib/pj/experiment.rb:56-70、`/data/list_of_genome.json` / 新: config/genomes.yml:2-16、`/api/genomes`、frontend/components/genome-tabs.ts:46-60
- **確認方法**: curl+ソース確認済み
- **備考**: SHIKINEN-SENGU.md 記載の意図的変更。TAIR12 は本番の `/data/experiment_types?genome=TAIR12` で全件 null (本番 DB に無い)。

### PB-05 `#genome=<code>` ディープリンク (新機能) と URL の書き換え
- **ページ/機能**: Peak Browser > ゲノムタブ
- **旧 (chip-atlas.org)**: URL ハッシュは無視。常に hg38 で開く。選択状態を URL で共有する手段なし
- **新 (localhost:9292)**: `/peak_browser#genome=mm10` で mm10 タブを開いた状態になる。ただしタブ以外 (トラック種別・細胞種・閾値) はリンクできない。また通常アクセス時も `history.replaceState` で URL が `/peak_browser#genome=hg38` に書き換わる
- **分類**: 新機能
- **影響度**: 中
- **根拠**: 新: frontend/components/genome-tabs.ts:8-17, 26-30, 79-82
- **確認方法**: ソース推定 (要ブラウザ確認: 書き換え後の URL 表示)

### PB-06 パネルの実装 (panel → card) と JS 実行前の見え方
- **ページ/機能**: Peak Browser > 各パネル
- **旧 (chip-atlas.org)**: Bootstrap 3 `.panel.panel-default`。"2. Cell type Class" には "All cell types" がサーバ側で描画済み。10 ゲノム分のパネルを全部サーバ描画 (33 KB)
- **新 (localhost:9292)**: `.card` を BS3 風に上書き。全パネルの中身は JS が描画するまで空 (`<div id="facet-…">`)。1 セットのみ (11 KB)
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:75-125 / 新: views/peak_browser.erb:24-59、public/css/style.css:473-497
- **確認方法**: curl+ソース確認済み (要ブラウザ確認: 描画までのちらつき)

### PB-07 件数の桁区切り
- **ページ/機能**: Peak Browser > 1./2. および (optional) パネルの件数表示
- **旧 (chip-atlas.org)**: "ChIP: Histone (36073)" (生の数値)
- **新 (localhost:9292)**: "ChIP: Histone (36,073)" (`toLocaleString()`、閲覧環境のロケール依存)
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:43-45 / 新: frontend/components/list-box.ts:52-55
- **確認方法**: ソース推定

### PB-08 件数 null の表示 "(null)"
- **ページ/機能**: Peak Browser > 1. Track type class
- **旧 (chip-atlas.org)**: count が null のとき文字列連結で "ATAC-Seq (null)" と表示される (本番 10 ゲノムは現在すべての種別に件数があるため通常は出ない)
- **新 (localhost:9292)**: count null は件数を付けずラベルのみ表示。新版は PB-09 の双方向更新で null が頻繁に発生する (例: Blood 選択時の "Annotation tracks")
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:43-45、本番 `/data/experiment_types?genome=TAIR12` (全 null) / 新: frontend/components/list-box.ts:52-55、`/api/track_classes?genome=hg38&cell_type_class=Blood` (Annotation tracks: null)
- **確認方法**: curl+ソース確認済み

### PB-09 細胞種クラス変更時のトラック種別件数の再計算 (双方向)
- **ページ/機能**: Peak Browser > 1. Track type class ⇄ 2. Cell type Class
- **旧 (chip-atlas.org)**: `/data/experiment_types` はページ読込とタブ切替時にしか呼ばれない。細胞種クラスを変えても "1." の件数は変わらない
- **新 (localhost:9292)**: 細胞種クラス変更で `/api/track_classes?cell_type_class=…` を再取得し "1." の件数を更新 (Blood 選択で Histone 9,246、Annotation tracks は件数なし)。トラック種別変更時は旧版同様 "2." を更新
- **分類**: 改良
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:9-15, 293-307 / 新: frontend/components/facet-filter.ts:248-250, 252-260
- **確認方法**: curl+ソース確認済み
- **備考**: 件数なしの種別 (例: Blood + Annotation tracks) も選択可能で、その場合 URL は null になる (PB-24)。

### PB-10 選択状態の保持 (クラス変更・タブ切替)
- **ページ/機能**: Peak Browser > 全パネル
- **旧 (chip-atlas.org)**: トラック種別を変えると細胞種クラスは "All cell types" に戻る。タブを切り替えると (戻った場合も) そのゲノムの全リストが既定値に戻る
- **新 (localhost:9292)**: 再取得後も同じ id があれば選択を維持 (例: Blood を選んだまま TFs に変更しても Blood のまま、mm10→hg38 でも維持)。サブクラスも同名があれば維持
- **分類**: 改良
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:17-21, 72-82 (i==0 を選択) / 新: frontend/components/facet-filter.ts:152-164, 363-369
- **確認方法**: ソース推定 (要ブラウザ確認)
- **備考**: 旧版にはタブ切替時に前回の細胞種クラスで "1." の件数を計算しつつ "2." を既定値に戻す不整合があった (peak_browser.js:29, 72-82)。

### PB-11 保持された選択が新リストに無い場合の件数・サブクラスの不整合 (新版のみ)
- **ページ/機能**: Peak Browser > 1./2. および (optional) パネル
- **旧 (chip-atlas.org)**: 該当なし (毎回既定値に戻すため)
- **新 (localhost:9292)**: 例: mm10 で "Embryonic fibroblast" を選び hg38 タブへ → `loadTrackClasses` は旧値で件数を取得 (hg38 に無いので全件 null → 件数なしで表示)、その後 "2." は "All cell types" に落ちるが "1." の件数は再取得されない。トラック種別変更時も `Promise.all` で 3 リストを同時取得するため、"2." が既定値に落ちても (optional) 2 リストは旧細胞種クラスの内容のまま
- **分類**: 退行 (要修正)
- **影響度**: 低
- **根拠**: 新: frontend/components/facet-filter.ts:232-250 (initialLoad / reloadOnTrackChange の順序)
- **確認方法**: ソース推定 (要ブラウザ確認)
- **備考**: 修正案: 依存リストは親リストの解決後に取得する (initialLoad と同じ逐次化)。

### PB-12 type-to-search の一致方式・候補表示
- **ページ/機能**: Peak Browser > Track type (optional) / Cell type (optional) の "type to search"
- **旧 (chip-atlas.org)**: typeahead.js 0.11.1 + Bloodhound (トライ木)。空白区切りトークンの**前方一致** ("K4me3" は "H3K4me3" に一致しない)、大文字小文字無視、1 文字から、候補 15 件、入力欄内に灰色ヒント + 一致部分ハイライト。候補選択 (`typeahead:select`) または入力がラベルと完全一致したとき (`keyup`) にリストボックスを同期。不一致文字列なら候補なし・リストは変化なし
- **新 (localhost:9292)**: 自前 Autocomplete。**部分一致**、大文字小文字無視、フォーカスしただけで先頭 50 件のドロップダウンが開く、最大 50 件、ヒント/ハイライトなし、↑↓/Enter/Esc 対応、`role=combobox`/`listbox`/`aria-activedescendant`。候補文字列は option のテキストなので件数付き ("H3K4me3 (5,678)")。入力に応じて下のリストボックスの非一致行を `hidden` にして絞り込む。不一致なら候補は閉じ、リストボックスは全行非表示 (空に見える)、選択値は変わらない。Enter で先頭候補を選択、選択時に `change` を発火
- **分類**: 改良
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:197-227、old-app/public/js/typeahead.bundle.js (trie 実装) / 新: frontend/pages/peak-browser.ts:75-111、frontend/components/autocomplete.ts:24, 55-66, 139-162, 170-172, 190-195
- **確認方法**: ソース推定 (要ブラウザ確認: ドロップダウンがリストボックスに重なる見え方)
- **備考**: 旧版では Input control/ATAC-Seq/DNase-seq/Bisulfite-Seq に切り替えたとき typeahead が再構築されず、前の種別の抗原名が候補に残るバグがあった (peak_browser.js:98-109 で `activateTypeAhead` を呼ばない)。新版では解消。

### PB-13 Flexselect は旧版でも未使用 (見た目は同じ素の `<select size=8>`)
- **ページ/機能**: Peak Browser > (optional) パネルのリストボックス
- **旧 (chip-atlas.org)**: `select.flexselect` に jquery.flexselect.js / liquidmetal.js を読み込むが `.flexselect()` を一度も呼ばない (grep 0 件) → 素のリストボックス
- **新 (localhost:9292)**: ListBox (素の `<select size=8 class="form-control list-box">`)
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:92, 114, 143-144、old-app/public/js/pj/*.js に `flexselect(` 0 件 / 新: frontend/components/list-box.ts:31-34
- **確認方法**: ソース確認済み
- **備考**: 新版コメント (peak-browser.ts:5-6 "production's old Flexselect affordance") は実態と異なる。

### PB-14 Input control / ATAC-Seq / DNase-seq / Bisulfite-Seq の "Track type (optional)"
- **ページ/機能**: Peak Browser > Track type (optional)
- **旧 (chip-atlas.org)**: これら 4 種別では API を呼ばず "NA" 1 行 (値 "-") のみ表示 → 誤った組合せを選べない
- **新 (localhost:9292)**: API の結果をそのまま表示: "All" + "ATAC-Seq (48,822)" / "DNase-Seq (4,604)" / "Bisulfite-Seq (26,746)" / "Input control (18,190)"。ATAC-Seq・DNase-Seq・Bisulfite-Seq のサブクラスを選ぶと対応する bedfile 行が無く `{"url":null}` (ローカル API で確認) → Download は `/null` (404) へ、IGV は `file=` 空 (PB-24)。"Input control" サブクラスだけは `InP.ALL.05.Input_control.AllCell.bed` に解決する (旧版 UI では選べなかったファイル)
- **分類**: 退行 (要修正)
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:98-109 / 新: frontend/components/facet-filter.ts:213-216 (種別ごとの分岐なし)、`/api/track_subclasses?genome=hg38&track_class=ATAC-Seq`、`POST /api/download_url` (ATAC-Seq/"ATAC-Seq" → null)、sqlite: bedfiles の track_subclass は ATAC-Seq/DNase-seq/Bisulfite-Seq で "-" のみ、Input control は "-" と "Input control"
- **確認方法**: curl+ソース確認済み

### PB-15 Annotation tracks 選択時のパネル表示
- **ページ/機能**: Peak Browser > Annotation tracks 選択時の 2./(optional)/3.
- **旧 (chip-atlas.org)**: "2. Cell type Class" は "NA" 1 行 (値 NA)、"Track type (optional)" は "All" を除き先頭のアノテーション ("CAGE (fanta.bio): Enhancer") を選択済み、件数表示なし、"Cell type (optional)" は "NA"、"3." は "NA" 1 行 (値 anno)
- **新 (localhost:9292)**: "2." は "All cell types (308)" / "NA (308)"、"Track type (optional)" は "All" (選択済み) + 各アノテーション "(1)" 付き、"Cell type (optional)" は "All"、"3." は 50/100/200/500
- **分類**: 単なる変更 (機能面の帰結は PB-22)
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:63-70, 127-138, 177-182, 255-262 / 新: `/api/cell_type_classes?genome=hg38&track_class=Annotation%20tracks`、`/api/track_subclasses?…`、frontend/components/facet-filter.ts:223-230
- **確認方法**: curl+ソース確認済み

### PB-16 抗原と細胞種の相互排他 (警告 "Either an "Antigen" or a "Cell type" is selectable.") の消失
- **ページ/機能**: Peak Browser > Track type (optional) × Cell type (optional)
- **旧 (chip-atlas.org)**: 一方で "All" 以外を選ぶと他方が "-" (All) に戻り、パネル上部に閉じられる `alert-warning` "Either an "Antigen" or a "Cell type" is selectable." を表示 (リストボックスの change 時)
- **新 (localhost:9292)**: 制約も警告も無い。両方選ぶと (bedfiles に両方指定の行は 0 件) `POST /api/download_url` → `{"url":null}`、`POST /api/igv_url` → `…&file=` (空)。Download ボタンは `/null` へ遷移し 404 ページ、IGV は空ファイルの load コマンドを送る
- **分類**: 退行 (要修正)
- **影響度**: 高
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:318-360 (メッセージ :344) / 新: frontend/pages/peak-browser.ts:50-61, 187-199 (null チェックなし)、ローカル API 結果 (Histone/H3K4me3/Blood/K-562 → null)、sqlite: `track_subclass<>'-' and cell_type_subclass<>'-'` は 0 行
- **確認方法**: curl+ソース確認済み
- **備考**: 旧版も typeahead 経由で両方選んだ場合は警告が出ない (イベントは select 要素にしか束縛されていない) が、リストボックス操作では防いでいた。修正案: 旧版同様の相互排他 + 警告、または `url === null` を検出してボタン下に「この組合せの BED ファイルはありません」と表示。

### PB-17 ⓘ (Threshold) の表示方式
- **ページ/機能**: Peak Browser > 3. Threshold for Significance の ⓘ
- **旧 (chip-atlas.org)**: `alert()` (モーダル)。`<a class="infoBtn">` は href なしでキーボードフォーカス不可
- **新 (localhost:9292)**: Bootstrap 5 popover (クリック/フォーカスで表示、上側)。`href="#" role="button" aria-label="About the significance threshold"`。本文は旧版と完全一致
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:122-123、old-app/public/js/pj/peak_browser.js:424-425, 430-435 / 新: views/peak_browser.erb:56、frontend/pages/peak-browser.ts:33-36, 164、frontend/components/info-popover.ts:37-46、文字列比較 (identical: True)
- **確認方法**: curl+ソース確認済み (要ブラウザ確認: popover の表示位置)

### PB-18 Bisulfite-Seq の閾値 "NA (bs)" が無くなり URL が生成できない
- **ページ/機能**: Peak Browser > 3. Threshold for Significance (Bisulfite-Seq) → View on IGV / Download BED file
- **旧 (chip-atlas.org)**: Bisulfite-Seq を選ぶと "3." は "NA" 1 行 (値 `bs`) になり、`POST /download` は `…/hg38/assembled/BSF.ALL.bs.AllAg.AllCell.bed` を返す (archive HEAD 200)
- **新 (localhost:9292)**: "3." は常に 50/100/200/500 (値 05/10/20/50)。既定の "05" で `POST /api/download_url` → `{"url":null}`、`POST /api/igv_url` → `http://localhost:60151/load?genome=hg38&file=` (空)。結果: Download ボタンは `/null` へ遷移し 404 ページ、IGV は空の load。`qval:"bs"` を送れば正しい URL が返るので、欠けているのはフロントの種別分岐のみ
- **分類**: 退行 (要修正)
- **影響度**: 高 (hg38 で 26,746 実験分の DNA メチル化トラックが Peak Browser から取得不能)
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:245-253 / 新: frontend/components/facet-filter.ts:223-230, 159-164 (qval は `/api/qval_range` 固定)、ローカル API 結果、sqlite: `bedfiles` の Bisulfite-Seq は qval `bs` のみ 1,019 行
- **確認方法**: curl+ソース確認済み
- **備考**: `/api/qval_range` 自体が Bisulfite-Seq/Annotation tracks を除外しているのは旧版 (`/qvalue_range`) と同じ (lib/models/bedfile.rb:38-46)。Enrichment Analysis 側 (frontend/pages/enrichment-analysis.ts:400) には `'bs'` の分岐が実装されているので、同じ規則を FacetFilter に入れれば良い。

### PB-19 Annotation tracks が新版では使えない (qval "anno" 不送信 + 既定 "All" + IGV API 500)
- **ページ/機能**: Peak Browser > Annotation tracks → View on IGV / Download BED file
- **旧 (chip-atlas.org)**: agSubClass=先頭アノテーション, clClass=NA, qval=anno を送信 → `PJ::Location#archived_annotation_url` が clClass を 'All cell types' に**上書きしてから** `get_trackname` が評価される (文字列補間の評価順) → `…/data/annotations/hg38/<file>` と `…/load?…&name=<trackname>` を返す
- **新 (localhost:9292)**: (a) 送信 qval は "05" (bedfiles の Annotation tracks は `anno` のみ 544 行) → 不一致。(b) 既定の track_subclass は "All" (`-`) で該当行なし。(c) `LocationService#igv_browsing_url` は `annotation_url` より先に、cell_type_class を 'All cell types' へ merge しない `@condition` で `Bedfile.get_trackname` を呼ぶため、行が無いと `Bedfile::NotFound` が rescue されず **HTTP 500** (開発環境ではスタックトレースがそのまま返る)。UI: View on IGV → "Failed to build IGV link."、Download → `{"url":null}` → `/null` 404。qval "anno" + 具体的なアノテーション + "All cell types" を送れば正しい URL が返る (`cpg_island.bed.gz`、HEAD 200) が、cell_type_class "NA" + anno だと igv_url は依然 500 (download_url は成功)
- **分類**: 退行 (要修正)
- **影響度**: 高
- **根拠**: 旧: old-app/lib/pj/location.rb:30-36, 58-60、old-app/public/js/pj/peak_browser.js:127-138, 255-262 / 新: lib/services/location_service.rb:22-31 (:26 が先), 88-94、lib/models/bedfile.rb:20-24、frontend/components/facet-filter.ts:223-230、ローカル API 結果 (POST igv_url Annotation/"-"/All/05 → HTTP 500; CpG Islands/NA/anno → 500; CpG Islands/All/anno → 200)
- **確認方法**: curl+ソース確認済み
- **備考**: 修正案: FacetFilter で Annotation tracks 時に qval を `anno` 固定・"All" を除外、`igv_browsing_url` は merge 済み condition で `get_trackname` を呼び NotFound を rescue する。

### PB-20 View on IGV: IGV 起動確認と未起動時のメッセージ
- **ページ/機能**: Peak Browser > View on IGV
- **旧 (chip-atlas.org)**: `POST /browse` → `window.open(url, "_self")` で現在のタブを `http://localhost:60151/load?genome=…&file=…` へ遷移。IGV 未起動ならブラウザの接続エラーページ ("cannot open the page" 等) になり ChIP-Atlas のページと選択状態を失う。起動中なら IGV の応答 ("OK" のテキスト) が表示される
- **新 (localhost:9292)**: `POST /api/igv_url` 後、`fetch("http://localhost:60151/echo", {mode:"no-cors"})` (2 秒 timeout) で到達確認。失敗時はページ内 (`#action-status`, aria-live) に "Could not reach IGV on localhost:60151. Start IGV on this machine and make sure "Enable port" is on under View › Preferences › Advanced, then try again." と表示しページに留まる。成功時は旧版同様 `window.location.href = url` で遷移。途中経過 "Building IGV link…" → "Contacting IGV…"
- **分類**: 改良
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:371-416 (:406) / 新: frontend/pages/peak-browser.ts:166-185、frontend/components/igv.ts:20-42
- **確認方法**: ソース推定 (要ブラウザ確認: 下記)
- **備考**: 到達確認は「公開 https サイト → loopback への cross-origin fetch」であり、Chrome の Local Network Access 許可プロンプト (拒否時は fetch 失敗) や Safari の mixed content 扱いによっては IGV 起動中でも "Could not reach IGV" になり得る (推定)。旧版の top-level 遷移はこの制約を受けない。実ブラウザでの確認が必須。IGV 起動中に "OK" ページへ遷移して ChIP-Atlas を離れる点は新旧同じ。旧版の `button.prop("disable", true)` は typo で無効化されておらず、新版もボタンは無効化しない。

### PB-21 "Error connecting to IGV?" の内容とリンク先
- **ページ/機能**: Peak Browser > View on IGV 下のリンク
- **旧 (chip-atlas.org)**: クリックで `confirm()`: "IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data.\n\nClick OK to go to the IGV website, or cancel to back to ChIP-Atlas." → OK で https://igv.org/doc/desktop/#DownloadPage/ を新規タブで開く
- **新 (localhost:9292)**: 単なるリンク `https://github.com/inutano/chip-atlas/wiki#igv_doc` (新規タブ)。wiki Home に `igv_doc` アンカーは無く (0 件)、"60151"/"enable port" の記述も無い → wiki 先頭に着地するだけで、port 設定手順は View on IGV 失敗後の PB-20 メッセージでしか見られない
- **分類**: 退行 (要修正)
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:426-427, 436-439 / 新: views/peak_browser.erb:64-65、curl https://github.com/inutano/chip-atlas/wiki (アンカー一覧に igv_doc なし)
- **確認方法**: curl+ソース確認済み
- **備考**: 修正案: 旧版の手順文を popover で表示するか、wiki に該当節を作りアンカーを合わせる。

### PB-22 Download BED file の URL 生成 (.bed/.bed.gz の解決)
- **ページ/機能**: Peak Browser > Download BED file
- **旧 (chip-atlas.org)**: `POST /download` → `filename + ".bed"` 固定 (`…/data/<genome>/assembled/<file>.bed`) → `window.open(url,"_self")` で遷移 (Content-Type `application/vnd.realvnc.bed` のためダウンロードになる)
- **新 (localhost:9292)**: `POST /api/download_url` → `BedExtensionResolver` が archive に HEAD を打ち `.bed` → `.bed.gz` の順で 200 を探す (確定 1 時間キャッシュ、失敗時は `.bed` を仮採用し 5 秒キャッシュ) → `window.location.href = url`。hg38/mm10/sacCer3 は `.bed` (archive: .bed 200 / .bed.gz 404) で旧版と同一 URL。TAIR12 は `.bed.gz` (archive: .bed 404 / .bed.gz 200)
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: old-app/lib/pj/location.rb:17-19, 38-43 / 新: lib/services/location_service.rb:80-86、lib/services/bed_extension_resolver.rb:27-31, 81-106、ローカル API 結果、archive HEAD 結果 (pb/ 参照)
- **確認方法**: curl+ソース確認済み
- **備考**: 初回は (genome, filename) ごとに最大 2 回の HEAD (open/read 各 2 秒) が入るためボタン応答が遅れ得る。archive 停止時は `.bed` を返す (旧版と同じ)。

### PB-23 該当ファイルが無いときの挙動 (`{"url":null}` → `/null` 404)
- **ページ/機能**: Peak Browser > View on IGV / Download BED file
- **旧 (chip-atlas.org)**: `PJ::Bedfile.get_filename` が NameError → `archive_url` nil → `{"url":null}` → `window.open(null,"_self")` → 相対 URL "null" → `/null` (HTTP 404、"ChIP-Atlas: 404 / Sorry, could not find the requested resource. Try with different data or contact us." + giphy)。IGV は `…&file=` (空)。ボタン無効化やアラートは無い
- **新 (localhost:9292)**: 同じく `{"url":null}` → `window.location.href = null` → `/null` (HTTP 404、同文 + "Back to Home" / "Report Issue" ボタン)。IGV は `…&file=`。`url === null` の検査は無く、`status.textContent = ''` にしてから遷移する
- **分類**: 退行 (要修正)
- **影響度**: 中
- **根拠**: 旧: old-app/lib/pj/location.rb:38-43、old-app/public/js/pj/peak_browser.js:406、本番 `/null` 404 / 新: lib/services/location_service.rb:80-86、frontend/pages/peak-browser.ts:179-180, 193-194、`curl localhost:9292/null` 404、views/not_found.erb:7-12、test/services/location_service_test.rb:76-83 (nil を仕様として固定)
- **確認方法**: curl+ソース確認済み (遷移そのものは要ブラウザ確認)
- **備考**: 挙動自体は新旧同じだが、新版は PB-14/16/18/19 によりこの状態に到達しやすい。修正案: null なら遷移せず「この組合せの事前計算ファイルはありません」を `#action-status` に表示し、サーバ側 igv_url も null を返す。

### PB-24 API 失敗時のユーザ向けメッセージ
- **ページ/機能**: Peak Browser > View on IGV / Download BED file
- **旧 (chip-atlas.org)**: `$.ajax().fail` は `console.log("Error: failed to send/get data. Please contact from github issue")` のみ。画面には何も出ない
- **新 (localhost:9292)**: `#action-status` に "Failed to build IGV link." / "Failed to build download link." を表示 (console.error も)。PB-19 の 500 はこの経路で表示される。FacetFilter 未初期化時は "Select a track type first." (実質到達しない)
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/peak_browser.js:408-412 / 新: frontend/pages/peak-browser.ts:168, 181-184, 195-198
- **確認方法**: ソース確認済み

### PB-25 旧 URL・旧 API の廃止 (`/browse`, `/download`, `/qvalue_range`, `/data/*`)
- **ページ/機能**: Peak Browser が使っていたエンドポイント
- **旧 (chip-atlas.org)**: `POST /browse`, `POST /download`, `GET /qvalue_range`, `GET /data/experiment_types|sample_types|chip_antigen|cell_type`, `GET /data/list_of_genome.json` が存在
- **新 (localhost:9292)**: いずれも 404 (HTML)。代替は `/api/igv_url`, `/api/download_url`, `/api/qval_range`, `/api/track_classes|cell_type_classes|track_subclasses|cell_type_subclasses`, `/api/genomes` (パラメータは snake_case: `track_class`, `cell_type_class`)
- **分類**: 機能削除
- **影響度**: 低 (UI 利用者には影響なし。旧 API を直接叩く外部スクリプトには影響)
- **根拠**: 旧: old-app/app.rb:147-183, 227-230, 243-258 / 新: routes/api.rb:58-80, 103-106, 133-153、curl 結果
- **確認方法**: curl+ソース確認済み
- **備考**: BRIEF 記載の意図的変更。

### PB-26 `GET /api/igv_url` / `GET /api/download_url` (エージェント向け) の追加
- **ページ/機能**: Peak Browser の URL 生成 API
- **旧 (chip-atlas.org)**: POST のみ (JSON ボディ)
- **新 (localhost:9292)**: GET (`?genome=&track_class=&track_subclass=&cell_type_class=&cell_type_subclass=&qval=`) でも同じ結果を返す。`genome`/`track_class` 欠落は 400 JSON。POST は `condition` 欠落で 400 `{"error":"condition object required"}`
- **分類**: 新機能
- **影響度**: 低
- **根拠**: 新: routes/api.rb:133-153、curl 結果
- **確認方法**: curl+ソース確認済み

### PB-27 キーボード操作・ARIA
- **ページ/機能**: Peak Browser 全体
- **旧 (chip-atlas.org)**: タブは `<a role=tab data-toggle=tab>`、Tutorial は div (フォーカス不可)、ⓘ と "Error connecting to IGV?" は href なし `<a>` (フォーカス不可)、`id="hg38agSubClass"` が div/input/select の 3 要素に重複 (不正 HTML)。リストボックス・検索欄に `<label>` なし (placeholder のみ)
- **新 (localhost:9292)**: タブは `<button role=tab aria-selected>`、Tutorial は `<button>`、ⓘ は `href="#" role=button aria-label` + フォーカスで popover、状態表示は `aria-live="polite"`、検索欄は `role=combobox aria-autocomplete=list aria-activedescendant`、候補は `role=listbox/option`、id は一意 (`facet-…-select`)。ただしリストボックス 5 つと検索欄 2 つには依然 `<label>`/`aria-labelledby` が無く、パネル見出しと関連付けられていない
- **分類**: 改良
- **影響度**: 中
- **根拠**: 旧: old-app/views/peak_browser.haml:44, 89-92, 122, 130 / 新: frontend/components/genome-tabs.ts:51-56、views/peak_browser.erb:56, 68、frontend/components/autocomplete.ts:170-172, 88-96、frontend/components/list-box.ts:31-34
- **確認方法**: ソース確認済み (要ブラウザ確認: フォーカスリング、スクリーンリーダ読み上げ)

### PB-28 レスポンシブ挙動・ボタン間隔
- **ページ/機能**: Peak Browser > レイアウト
- **旧 (chip-atlas.org)**: Bootstrap 3 `.col-md-4` (3 列は ≥992px、以下は 1 列)。ボタンは `.button-submit.down button { margin-top: 2em }` で 2 つとも上 2em、"Error connecting to IGV?" は `pull-right`
- **新 (localhost:9292)**: Bootstrap 5 `.col-md-4` (3 列は ≥768px)。768〜991px では新版のみ 3 列 (各列が狭い)。ボタンは `.button-submit .btn + .btn { margin-top: 5px }`、リンクは block 右寄せ 13px。`.btn-block` は独自 CSS で復元済み。コンテナ幅 1170px は共通
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: old-app/views/style.sass:86-100、old-app/views/peak_browser.haml:73, 94, 116, 127-133 / 新: views/peak_browser.erb:23, 37, 51、public/css/style.css:433-440
- **確認方法**: ソース推定 (要ブラウザ確認: 768〜991px と 400px)

### PB-29 選択肢取得中のインジケータ / JS 無効時
- **ページ/機能**: Peak Browser > 各パネル
- **旧 (chip-atlas.org)**: 読込中表示なし。JS 無効でも見出し・空のリストボックス・"All cell types"・ボタンは見える
- **新 (localhost:9292)**: 読込中表示なし。JS 無効ではタブもリストも描画されず、空のカードとボタンのみ
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: old-app/views/peak_browser.haml:61-125 / 新: views/peak_browser.erb:20-59
- **確認方法**: curl+ソース確認済み

---

## 要ブラウザ確認リスト

1. **PB-20 (最優先)**: 本番相当の https 配信で、IGV 起動中に "View on IGV" を押したとき `fetch(http://localhost:60151/echo)` が Chrome (Local Network Access 許可プロンプト)、Firefox、Safari (mixed content) でそれぞれ成功するか。拒否/ブロック時に "Could not reach IGV…" が誤表示されないか。IGV 未起動時のメッセージ表示。
2. PB-16 / PB-18 / PB-19 / PB-23: 実際に `/null` へ遷移して 404 ページが出ること、Annotation tracks で "Failed to build IGV link." が出ること。
3. PB-12: 検索欄フォーカス時に 50 件のドロップダウンがリストボックスに重なる見え方、不一致入力でリストボックスが空になる挙動、Enter/↑↓ の操作感。
4. PB-05: 通常アクセス時に URL が `#genome=hg38` に書き換わること、`#genome=mm10` 直リンク。
5. PB-10 / PB-11: ゲノムタブ往復・種別変更時の選択保持と件数不整合。
6. PB-02 / PB-06 / PB-17 / PB-28: 見出し下の罫線、カードの見た目、popover の位置、768〜991px と 400px のレイアウト、ボタン間隔。
7. PB-27: Tab キーでの到達順、フォーカスリング、`aria-live` の読み上げ。

## 未確認・不確実事項

- Chrome の Local Network Access (loopback への fetch に対する許可プロンプト) と Safari の localhost 扱いは記憶に基づく推定で、実機で未検証 (PB-20)。
- 本番の `bedfiles` テーブル内容は直接確認できない。Bisulfite-Seq = `bs`、Annotation tracks = `anno` という qval は新版 DB (`database.sqlite.verify`) と旧版 JS の送信値から判断した。本番 archive に `BSF.ALL.bs.AllAg.AllCell.bed` (HEAD 200) が存在することは確認済み。
- 旧版の hg19/mm9/dm3/ce10 の選択肢は比較していない (新版に存在しないため)。
- 選択肢の一致確認は hg38/mm10/sacCer3 と一部条件のサンプルであり、全ゲノム×全クラスの網羅比較ではない。ただし比較した範囲では件数まで完全一致した。
- `window.location.href = null` / `window.open(null,"_self")` が `/null` に遷移することは WebIDL の文字列変換規則からの推定で、ブラウザで未確認。
- 新版が IGV 到達確認に使う `/echo` コマンドへの IGV の応答内容 (IGV 未検証)。
- 範囲外だが気づいた点: 新版ナビバーに旧版の "Agents" リンクが無い (ナビバー担当の確認事項)。
