# Enrichment Analysis (EA) 新旧比較レポート

## 担当範囲の要約

- 対象: セットアップページ `/enrichment_analysis` (GET/POST)、ジョブ投入、結果ページ `/enrichment_analysis_result`、ログ表示。本番には GET のみ、ローカルには GET と「送信前に必ず失敗する」リクエストのみ行い、WABI/WES へのジョブ投入は一切していない。
- 6 パネル構成・見出し・タイトル初期値 (My project / Dataset A / Dataset B)・閾値ラベル (50/100/200/500)・実験タイプ/細胞型クラスの語彙と件数・推定実行時間の計算式とその参照データ (`/api/bed_sizes` は本番 `number_of_lines.json` と共通キー 2,895 件で値の差ゼロ)・WABI へ送るフィールド名は本番と一致している。
- 一方で、実際に使う操作では差が大きい。特に (1) 遺伝子カウント表モードで `typeB` が本番の `"empty"` ではなく `"rnd"` で送られる、(2) ページ読込時の WABI 死活確認とボタン無効化が無く、結果ページもバックエンド停止を利用者に伝えない、(3) 「Try with example」がモードを無視して BED 例を強制し、dataset B 側の例・ファイル選択が消えている、(4) Bisulfite-Seq 選択時の閾値 "NA"(999) が無い、(5) 「node status (epyc.q)」のリンク先が 404、の 5 点は修正が必要と判断した。
- 本番の旧 URL 形式 (`?id=…&api=wabi`) は新版では「Missing id or backend parameter」になる (結果 URL の有効期間は 1 週間なので移行期に限られるが要対応)。外部から POST される `taxonomy` によるゲノムタブ切替も新版では機能しない。
- 改良点: 結果ページの「Submitted at」が WABI の ID から復元される (本番は再訪時刻を表示してしまう)、URL パラメータのエンコード、空データの事前検出、ログの HTML 解釈回避、終了後のポーリング停止、双方向のファセット更新。
- 件数: 改良 7 / 単なる変更 23 / 機能削除 3 / 退行 (要修正) 12 / データ差分 1 / 新機能 3 (計 49 項目)。
- 注意: `SCR/old-app/views/enrichment_analysis.haml:250` は "node status (short.q)" だが、本番が配信する HTML は "node status (epyc.q)" である。本番 HTML を正として比較した (スナップショットと本番の差は「未確認・不確実事項」に記載)。

---

## A. セットアップページ — ヘッダ・ゲノムタブ

### EA-01 ゲノムタブの構成 (10 → 7)
- **ページ/機能**: Enrichment Analysis > ゲノムタブ
- **旧 (chip-atlas.org)**: `H. sapiens (hg38)`, `H. sapiens (hg19)`, `M. musculus (mm10)`, `M. musculus (mm9)`, `R. norvegicus (rn6)`, `D. melanogaster (dm6)`, `D. melanogaster (dm3)`, `C. elegans (ce11)`, `C. elegans (ce10)`, `S. cerevisiae (sacCer3)` の 10 タブ。
- **新 (localhost:9292)**: `hg38, mm10, rn6, dm6, ce11, sacCer3, A. thaliana (TAIR12)` の 7 タブ。ラベル書式 (`H. sapiens (hg38)`) は同一。
- **分類**: `データ差分`
- **影響度**: 高
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:57-61, old-app/lib/pj/experiment.rb:56-68, https://chip-atlas.org/data/list_of_genome.json / 新: curl の `#page-data` JSON (`genomes` 7 件), `GET /api/genomes`
- **確認方法**: `curl+ソース確認済み`
- **備考**: BRIEF で意図的とされる変更。TAIR12 タブには example ファイルが無く (EA-13)、ⓘ の本文は旧アセンブリを列挙したまま (EA-22) なので、追加分・削除分の追従が不完全。

### EA-02 ゲノム選択の URL ハッシュ永続化
- **ページ/機能**: Enrichment Analysis > ゲノムタブ
- **旧 (chip-atlas.org)**: タブ選択は URL に残らない。再読込で hg38 に戻る。
- **新 (localhost:9292)**: タブ選択時に `#genome=<code>` を `history.replaceState` で書き込み、読込時にハッシュから復元する。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 新: frontend/components/genome-tabs.ts:8-17, 68, 80-81
- **確認方法**: `ソース推定`
- **備考**: 他ページ (Peak Browser 等) と共通部品。

### EA-03 ゲノムタブ切替時のフォーム状態
- **ページ/機能**: Enrichment Analysis > ゲノムタブ切替
- **旧 (chip-atlas.org)**: ゲノムごとに独立したパネル一式 (DOM) を持つ。タブをクリックすると `positionBed()`・リスト再生成・`putDefaultTitles()` が走り、そのゲノムのフォームは BED モード/タイトル初期値に戻る。textarea の内容はゲノムごとに保持される (別ゲノムのタブに貼った内容は混ざらない)。
- **新 (localhost:9292)**: フォームは 1 組のみ。タブ切替でファセット (実験タイプ/細胞型/閾値) だけ再読込し、dataset A/B の textarea・モード・タイトル・TSS 距離はそのまま残る。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:65-250 (ゲノムごとのループ), old-app/public/js/pj/enrichment_analysis.js:157-168 / 新: views/enrichment_analysis.erb:27-138 (単一フォーム), frontend/pages/enrichment-analysis.ts:702-711
- **確認方法**: `ソース推定` (要ブラウザ確認)
- **備考**: hg38 の BED を貼った後に mm10 タブへ移ると、その BED が mm10 として投入できてしまう。旧は空欄から始まるので同じ誤りは起きにくい。

### EA-04 ヘッダ文言と meta description
- **ページ/機能**: Enrichment Analysis > ページヘッダ
- **旧 (chip-atlas.org)**: h1 `ChIP-Atlas: Enrichment Analysis`、リード `Identify common epigenetic features of a given set of genomic loci and genes` (末尾ピリオド無し)。`<meta name="description">` は `Perform enrichment analysis based on the public ChIP-Seq peak call results.`
- **新 (localhost:9292)**: h1 同一、リード末尾にピリオド `… loci and genes.`。meta description は `Identify common epigenetic features of a given set of genomic loci and genes.`。`<title>` は両者 `ChIP-Atlas: Enrichment Analysis` で同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:8, 31-35 / 新: views/enrichment_analysis.erb:3, 17-18, views/layout.erb:6-8, curl 結果
- **確認方法**: `curl+ソース確認済み`

### EA-05 Tutorial ドロップダウン
- **ページ/機能**: Enrichment Analysis > Tutorial ボタン
- **旧 (chip-atlas.org)**: `Tutorial` ボタン → `PDF` (chip-atlas.dbcls.jp/data/manual/Enrichment_Analysis/Enrichment_Analysis.pdf), `Movie` (youtu.be/JBOB2PX5_-0), `Movie (統合TV, Japanese)` (doi.org/10.7875/togotv.2019.005)。h1 の右横 (col-md-2)。
- **新 (localhost:9292)**: 同じ 3 リンク・同じ文言。`rel="noopener noreferrer"` 付き。`_page_header.erb` で h1 の行の col-md-2 に配置 (docs/ui-parity-audit の「タブの下」記述は commit 66dc5db 以降古い)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:36-51 / 新: views/_tutorial.erb:7-25, views/_page_header.erb:13-29, curl 結果
- **確認方法**: `curl+ソース確認済み` (配置は要ブラウザ確認)

---

## B. パネル 1〜3 (実験タイプ・細胞型クラス・閾値)

### EA-06 実験タイプ一覧と件数表記
- **ページ/機能**: Enrichment Analysis > 1. Experiment type
- **旧 (chip-atlas.org)**: `/data/experiment_types` の結果から `Annotation tracks` を除いた 7 件を `size=8` のリストに表示。表記は `ChIP: Histone (36073)` (桁区切り無し)。先頭 `ChIP: Histone` が既定選択。CUT&Tag / CUT&RUN / Unclassified は無い。
- **新 (localhost:9292)**: `/api/track_classes` から `Annotation tracks` (id 一致) を除いた同じ 7 件。表記は `ChIP: Histone (36,073)` (toLocaleString)。既定選択は先頭で同一。CUT&Tag / CUT&RUN は新版にも無い (メニューから意図的に外した記録あり)。hg38/sacCer3 の各件数は本番と一致 (Histone 36073 / RNA polymerase 4263 / TFs and others 33368 / Input control 18190 / ATAC-Seq 48822 / DNase-seq 4604 / Bisulfite-Seq 26746)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:267-297 (283-291 で書式と除外), old-app/lib/pj/experiment.rb:72-107, https://chip-atlas.org/data/experiment_types?genome=hg38&clClass=All%20cell%20types / 新: frontend/pages/enrichment-analysis.ts:660-668, frontend/components/facet-filter.ts:198-206, frontend/components/list-box.ts:52-55, lib/models/experiment.rb:14-30, `GET /api/track_classes?genome=hg38`
- **確認方法**: `curl+ソース確認済み`
- **備考**: BRIEF の「CUT&Tag / CUT&RUN 追加」はこのメニューには反映されていない (lib/models/experiment.rb:14-20 に「メニュー項目は持たない」と明記)。public/llms.txt:3 は CUT&Tag/CUT&RUN を謳っており文書間で不整合。

### EA-07 細胞型クラス一覧と実験タイプ⇄細胞型の連動
- **ページ/機能**: Enrichment Analysis > 2. Cell type Class
- **旧 (chip-atlas.org)**: `All cell types (36073)` を先頭に、`Adipocyte … Unclassified … Uterus` (hg38/Histone で 22 件、Bisulfite-Seq では `No description` も含む)。実験タイプを変えると細胞型リストと閾値リストを再生成するが、細胞型を変えても実験タイプ側の件数は更新されない。
- **新 (localhost:9292)**: 一覧・件数は本番と完全一致 (hg38 Histone 22 件、Bisulfite-Seq 23 件を curl で照合)。細胞型を変えると実験タイプ側の件数も絞り込まれる (例: Adipocyte → `ChIP: Histone (327)`)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:259-265, 299-325, https://chip-atlas.org/data/sample_types?genome=hg38&agClass=Histone / 新: frontend/components/facet-filter.ts:244-271, `GET /api/cell_type_classes?genome=hg38&track_class=Histone`, `GET /api/track_classes?genome=hg38&cell_type_class=Adipocyte`
- **確認方法**: `curl+ソース確認済み`

### EA-08 Bisulfite-Seq 選択時の閾値 (旧 "NA"=999 が無い)
- **ページ/機能**: Enrichment Analysis > 3. Threshold for Significance
- **旧 (chip-atlas.org)**: 通常は `50 / 100 / 200 / 500` (既定 50、`/qvalue_range` の "05/10/20/50" を ×10 表示、option に value 属性が無いため送信値も表示値と同じ "50" 等)。実験タイプが `Bisulfite-Seq` のときはリストを `NA` 1 件 (value 999) に差し替え、`threshold=999` を送る。
- **新 (localhost:9292)**: 常に `50 / 100 / 200 / 500` (ファイルコード "05" 等を `qvalCodeToThreshold` で "50" 等に変換して送信。変換自体は本番と一致)。Bisulfite-Seq を選んでもリストは変わらず、`threshold` は選択中の 50〜500 が送られる。999 は送られない。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:970-999, 596-598 / 新: frontend/components/facet-filter.ts:223-230 (Bisulfite 分岐無し), frontend/pages/enrichment-analysis.ts:85-91, 602
- **確認方法**: `ソース推定`
- **備考**: ⓘ 本文は「Ignore if experiment type is set to Bisulfite-seq」と言うので WABI 側で無視される可能性はあるが、送信値が本番と異なることと、UI 上で意味の無い閾値が選べることは修正対象。推定実行時間のキーは両者とも `…,bs` を使うので推定は一致する (ts:397-402)。

### EA-09 閾値リストの表示行数
- **ページ/機能**: Enrichment Analysis > 3. Threshold for Significance
- **旧 (chip-atlas.org)**: `<select size="5">`。
- **新 (localhost:9292)**: ListBox 既定の `size=8` (4 件しか無いので余白が大きい)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:100 / 新: frontend/components/list-box.ts:34, facet-filter.ts:315
- **確認方法**: `ソース推定`

---

## C. パネル 4 (Enter dataset A)

### EA-10 dataset A ラジオの文言
- **ページ/機能**: Enrichment Analysis > 4. Enter dataset A
- **旧 (chip-atlas.org)**: `Genomic regions (BED)` / `Gene list (Gene symbols or IDs)` / `Gene count table (CSV or TSV)`。
- **新 (localhost:9292)**: `Genomic regions (BED)` / `Gene list (symbols or IDs)` / `Gene count table (CSV/TSV)`。既定は両者 BED。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:113-127 / 新: views/enrichment_analysis.erb:62-64
- **確認方法**: `curl+ソース確認済み`

### EA-11 textarea の placeholder と行数
- **ページ/機能**: Enrichment Analysis > 4./5. textarea
- **旧 (chip-atlas.org)**: placeholder `Click info buttons above to show the description format.`、`rows=8`。
- **新 (localhost:9292)**: placeholder `Paste content or use the file picker below.`、`rows=6`。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:131, 187 / 新: views/enrichment_analysis.erb:65, 88
- **確認方法**: `curl+ソース確認済み`

### EA-12 「Try with example」(dataset A) がモードを無視して BED 例を強制する
- **ページ/機能**: Enrichment Analysis > 4. Enter dataset A > Try with example
- **旧 (chip-atlas.org)**: 選択中のモードに応じて `/examples/<genome>/bedA.txt` (BED)、`geneA.txt` (遺伝子リスト)、`countA.txt` (カウント表) を読み込む。ラジオは変えない。
- **新 (localhost:9292)**: 常に `/examples/<genome>/bedA.txt` を読み込み、ラジオを `Genomic regions (BED)` に切り替える。遺伝子リスト例・カウント表例は読み込めない。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:338-370, 384-392 / 新: frontend/pages/enrichment-analysis.ts:631-646 (`bedA.txt` 固定、`dataA-bed` を checked)
- **確認方法**: `ソース推定` (要ブラウザ確認)
- **備考**: example ファイル自体は旧新で完全一致 (`diff -rq old-app/public/examples public/examples` 差分なし)。geneA.txt (100 行) / countA.txt (39,377 行) は新版でも配信されているが UI から辿れない。

### EA-13 TAIR12 タブに example が無い
- **ページ/機能**: Enrichment Analysis > TAIR12 タブ > Try with example
- **旧 (chip-atlas.org)**: TAIR12 タブ自体が無い (10 ゲノム全てに examples ディレクトリあり)。
- **新 (localhost:9292)**: `GET /examples/TAIR12/bedA.txt` → 404。クリックすると `Failed to load example data.` と表示される。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 新: `ls public/examples` (ce10 ce11 dm3 dm6 hg19 hg38 mm10 mm9 rn6 sacCer3 のみ), curl `http://localhost:9292/examples/TAIR12/bedA.txt` → 404, frontend/pages/enrichment-analysis.ts:635-645
- **確認方法**: `curl+ソース確認済み`
- **備考**: public/examples には使われない hg19/mm9/dm3/ce10 が残り、必要な TAIR12 が無い。

---

## D. パネル 5 (Enter dataset B)

### EA-14 dataset B の選択肢の出し分け方式
- **ページ/機能**: Enrichment Analysis > 5. Enter dataset B
- **旧 (chip-atlas.org)**: A のモードで表示を切り替える。BED: `Random permutation of dataset A` (既定) + `Genomic regions (BED)` のみ表示。Gene list: `Refseq coding genes (excluding dataset A)` (強制選択) + `Gene list (Gene symbols or IDs)` のみ表示 (Random/BED は非表示)。Count: 4 ラジオとも非表示で `Not required for gene count table analysis` のみ。
- **新 (localhost:9292)**: 4 ラジオを常時表示。Gene list モード以外では `Refseq coding genes (gene-list mode only)` / `Gene list (gene-list mode only)` を disabled 表示。Gene list モードでは Random/BED も選択可能 (旧 UI では選べない `gene + rnd` / `gene + bed` が投入できる。推定実行時間はこの組合せで `—`)。Refseq 選択時は補足 `All Refseq coding genes (excluding dataset A) are used.`、Random 選択時は `Random permutation needs no input.` を表示。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:151-201, old-app/public/js/pj/enrichment_analysis.js:394-486 / 新: views/enrichment_analysis.erb:79-90, frontend/pages/enrichment-analysis.ts:236-289, 484-522
- **確認方法**: `curl+ソース確認済み` (表示切替は要ブラウザ確認)
- **備考**: docs/ui-parity-audit-2026-09-14.md:174 は disabled ラジオを「改良として維持」と記録。`gene + rnd` の WABI 側の受け入れは未確認 (「未確認・不確実事項」参照)。

### EA-15 カウント表モードのパネル 5/6 表示
- **ページ/機能**: Enrichment Analysis > 4.=Gene count table 選択時
- **旧 (chip-atlas.org)**: パネル 5 は `Not required for gene count table analysis` のメッセージだけになり、Permutation times も消える。パネル 6 の `Dataset A title` / `Dataset B title` 欄は非表示になり、内部値は `Dataset A from count table header` / `Dataset B not applicable for count table` に置き換わる。TSS 距離欄は表示 (既定 5000)。
- **新 (localhost:9292)**: パネル 5 に `Random permutation of dataset A` がチェック済みで残り、`×1 ×10 ×100` と `Random permutation needs no input.` が表示される。`Not required …` は無い。`Dataset A title` / `Dataset B title` は表示されたままで既定値 `Dataset A` / `Dataset B` が送信される。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:452-486, old-app/views/enrichment_analysis.haml:198-201 / 新: frontend/pages/enrichment-analysis.ts:236-289 (count 分岐無し), views/enrichment_analysis.erb:79-91, 104-111
- **確認方法**: `ソース推定` (要ブラウザ確認)
- **備考**: 利用者に「カウント表でも permutation を選ぶ必要がある」と誤解させる。送信値の差は EA-16。

### EA-16 カウント表モードの送信値 (`typeB` が "empty" でない)
- **ページ/機能**: Enrichment Analysis > 送信ペイロード (typeA=count)
- **旧 (chip-atlas.org)**: `typeA=count` のとき `typeB="empty"`, `bedBFile="empty"` に強制 (コード上のコメント: "set dataset B to empty values as required by API")。`permTime` は常に送信 (既定 1)。
- **新 (localhost:9292)**: `typeB` は選択中の B ラジオ (既定 `rnd`) がそのまま送られ、`permTime` も付く。B に BED を選び textarea に入力すると `bedBFile` にその内容が入る。
- **分類**: `退行 (要修正)`
- **影響度**: 高
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:613-619 / 新: frontend/pages/enrichment-analysis.ts:594-623 (`typeB: form.bType`, 615 `permTime`), frontend/pages/enrichment-analysis.test.ts:153-159 (count でも B 由来の値を送る前提)
- **確認方法**: `ソース推定`
- **備考**: WABI 側がカウント表ジョブで `typeB=rnd` をどう扱うかは未検証 (ジョブ投入禁止のため)。本番コードが明示的に "empty" を要求している以上、同じ値を送るよう修正すべき。

### EA-17 dataset B の「Try with example」と「Choose local file」が無い
- **ページ/機能**: Enrichment Analysis > 5. Enter dataset B
- **旧 (chip-atlas.org)**: B 側にもファイル選択 (`Choose local file` キャプション付き) と `Try with example` があり、BED なら `bedB.txt` (1,997 行)、Gene list なら `geneB.txt` (150 行) を読み込む。
- **新 (localhost:9292)**: B 側はファイル入力 (`#dataB-file`, hidden 切替) のみ。キャプション `Choose local file` も `Try with example` も無い。`bedB.txt`/`geneB.txt` は配信されているが UI から辿れない。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:185-197, old-app/public/js/pj/enrichment_analysis.js:372-382 / 新: views/enrichment_analysis.erb:88-90 (link/caption 無し), frontend/pages/enrichment-analysis.ts:741-744 (`try-example` 1 箇所のみ)
- **確認方法**: `curl+ソース確認済み`
- **備考**: parity 記録 (docs/ui-parity-audit-2026-09-14.md:171) は A 側の復元のみ記載しており、B 側の欠落は意図的かどうか不明。

### EA-18 Permutation times の表記
- **ページ/機能**: Enrichment Analysis > 5. Random permutation
- **旧 (chip-atlas.org)**: ラベル `Permutation times` の後に `x1` (既定) `x10` `x100`。
- **新 (localhost:9292)**: ラベル無しで `×1` (既定) `×10` `×100` (乗算記号 U+00D7)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:157-165 / 新: views/enrichment_analysis.erb:80-84
- **確認方法**: `curl+ソース確認済み`

### EA-19 dataset B 選択の退避・復元
- **ページ/機能**: Enrichment Analysis > A のモード切替時の B の選択
- **旧 (chip-atlas.org)**: A を Gene list にすると B は必ず Refseq に、BED に戻すと必ず Random に強制される。
- **新 (localhost:9292)**: A を Gene list 以外に変えたとき B が Refseq/Gene list なら退避して Random に戻し、再び Gene list にしたときに退避した選択を復元する (退避が無ければ本番同様 Refseq)。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:411-417, 440-446 / 新: frontend/pages/enrichment-analysis.ts:166-188, 240-251, frontend/pages/enrichment-analysis.test.ts:199-295
- **確認方法**: `ソース推定`

---

## E. パネル 6 (Analysis description) と ⓘ

### EA-20 ⓘ ボタンの数 (12 → 8) と失われた説明文
- **ページ/機能**: Enrichment Analysis > 各パネルの ⓘ
- **旧 (chip-atlas.org)**: 1 ゲノム分で 12 個: 3.Threshold / A:BED / A:Gene list / A:Count / B:Random / B:BED / B:Refseq / B:Gene list / Analysis title / Dataset A title / Dataset B title / Distance range from TSS。
- **新 (localhost:9292)**: 8 個: 3.Threshold / A:BED / A:Gene list / A:Count / B:Random / B:BED / Analysis title / Distance range from TSS。残した 8 件の本文は本番の `helpText` と逐語一致 (note1/note2 の連結順も一致)。失われた 4 件の本文 (原文):
  - B:Refseq — `Check this to compare 'dataset A' with RefSeq coding genes, excluding those listed in 'dataset A'.`
  - B:Gene list — `Check this to compare 'dataset A' with another gene list.` + note1 (Acceptable identifiers …)
  - Dataset A title — `Enter a title for the data selected in "4. Enter dataset A".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).`
  - Dataset B title — 同文で `"5. Enter dataset B"`
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:97, 115, 121, 127, 155, 170, 177, 183, 213, 219, 225, 231; old-app/public/js/pj/enrichment_analysis.js:183-226, 1007-1037 / 新: views/enrichment_analysis.erb:49, 62-64, 79, 85, 101, 115; frontend/pages/enrichment-analysis.ts:35-61
- **確認方法**: `curl+ソース確認済み`
- **備考**: docs/ui-parity-audit-2026-09-14.md:171 の「seven ⓘ」は本番の実数 (12) と合わない。B:Refseq の説明は新版では選択時の補足文 (EA-14) で一部代替されている。

### EA-21 ⓘ の表示方式 (alert → popover) と改行
- **ページ/機能**: Enrichment Analysis > ⓘ
- **旧 (chip-atlas.org)**: `alert()` で改行付きの本文を表示 (例: `Example:\n  chr1<tab>531435<tab>543845\n  chr2<tab>…`)。
- **新 (localhost:9292)**: Bootstrap 5 popover (`trigger: 'focus click'`, `html: false`, placement top)。`.popover-body` に `white-space` 指定が無いため、本文中の `\n` は空白に潰れて 1 段落になると推定 (例示の表・箇条書きが読みにくくなる)。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:183-226 / 新: frontend/components/info-popover.ts:28-48, public/css/style.css:503-508 (.info-btn のみ), public/css/bootstrap5.min.css `.popover-body{padding…;color…}` (white-space 無し)
- **確認方法**: `ソース推定` (要ブラウザ確認)
- **備考**: `.popover-body { white-space: pre-line }` を足せば本番の見た目に近づく。

### EA-22 ⓘ 本文が新版のゲノム構成と合っていない
- **ページ/機能**: Enrichment Analysis > A:BED / B:BED / A:Gene list / A:Count の ⓘ
- **旧 (chip-atlas.org)**: note2 `Acceptable genome assemblies: hg19, hg38 (H. sapiens) / mm9, mm10 (M. musculus) / rn6 / dm3, dm6 / ce10, ce11 / sacCer3` は本番の 10 タブと一致。note1 の命名規則表は H. sapiens〜S. cerevisiae の 6 種。
- **新 (localhost:9292)**: 同文を逐語コピーしているため、提供していない hg19/mm9/dm3/ce10 を「acceptable」と案内し、提供している TAIR12 (A. thaliana) は載っていない。命名規則表にも A. thaliana (AGI locus code 等) が無い。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:1008-1011 / 新: frontend/pages/enrichment-analysis.ts:30-33 (NOTE1/NOTE2), `GET /api/genomes`
- **確認方法**: `curl+ソース確認済み`

### EA-23 Distance range from TSS の表記と入力型
- **ページ/機能**: Enrichment Analysis > 6. Distance range from TSS
- **旧 (chip-atlas.org)**: `- [ ] bp ≦ TSS ≦ + [ ] bp`、`type=text size=1`。BED モードでは非表示・値 0、Gene list/Count で表示・値 5000。
- **新 (localhost:9292)**: `- [ ] bp ≤ TSS ≤ + [ ] bp` (U+2266 → U+2264)、`type=number min=0 style=width:6rem`。表示条件・既定値 (0 / 5000) は同一。A のモード変更時だけリセットする点も同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:228-238, old-app/public/js/pj/enrichment_analysis.js:420, 448, 477, 535-539 / 新: views/enrichment_analysis.erb:112-124, frontend/pages/enrichment-analysis.ts:232-234, 276-288
- **確認方法**: `curl+ソース確認済み`

### EA-24 送信ボタンの文言と二重送信防止
- **ページ/機能**: Enrichment Analysis > 6. submit ボタン
- **旧 (chip-atlas.org)**: ラベル `submit` (小文字、btn-block)。クリック直後に `disabled`、応答完了 (`complete`) で再有効化。
- **新 (localhost:9292)**: ラベル `Submit` (d-grid で全幅)。クリック後にボタンを無効化しないため、応答待ちの間に再クリックすると同じジョブが二重投入され得る。状態は下の `#submit-status` に `Submitting…` と出るだけ。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:241-242, old-app/public/js/pj/enrichment_analysis.js:758-803 (760, 795-797) / 新: views/enrichment_analysis.erb:126-128, frontend/pages/enrichment-analysis.ts:748-791 (disabled 操作無し)
- **確認方法**: `ソース推定`

### EA-25 Estimated run time
- **ページ/機能**: Enrichment Analysis > 6. Estimated run time
- **旧 (chip-atlas.org)**: 初期表示 `Estimated run time: -`。`/data/number_of_lines.json` (4,924 キー) と閉形式の回帰式でクライアント計算。既定状態 (hg38 / Histone / All cell types / 50、空 textarea) で `13 mins`。未対応の組合せは `NaN hr`、リスト再生成のたびに JSON を再取得。
- **新 (localhost:9292)**: 初期表示 `Estimated run time: —`。同じ式・同じ定数 (TAIR12 分は独自導出) を移植し、`/api/bed_sizes` (3,127 キー) を 1 回だけ取得。既定状態で同じく `13 mins` (numRef 614,923,604 → 791 s)。未対応の組合せ (gene+rnd 等)・TAIR 以外の未知ゲノムは `—`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/enrichment_analysis.haml:243-246, old-app/public/js/pj/enrichment_analysis.js:805-948, 138, 294-296 / 新: views/enrichment_analysis.erb:129-131, frontend/pages/enrichment-analysis.ts:291-572, frontend/pages/enrichment-analysis.test.ts:316-557; データ照合: 本番 number_of_lines.json と /api/bed_sizes の共通 2,895 キーで値の差 0 (python 比較)
- **確認方法**: `curl+ソース確認済み` (表示は要ブラウザ確認)
- **備考**: docs/ui-parity-audit-2026-09-14.md:236 の「推定値は em dash のまま」は commit 365c960 以降古い。

### EA-26 「node status (epyc.q)」のリンク先が 404
- **ページ/機能**: Enrichment Analysis > 6. node status リンク
- **旧 (chip-atlas.org)**: `node status (epyc.q)` → https://sc.ddbj.nig.ac.jp/en/operation/job_queue_status/ (HEAD 200)。
- **新 (localhost:9292)**: `node status (epyc.q)` → https://sc.ddbj.nig.ac.jp/en/guides/software/GridEngine/ (HEAD 404)。結果ページ側 (views/enrichment_analysis_result.erb:46) は本番と同じ job_queue_status を使っており、セットアップページだけ異なる。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: 本番 HTML (old-ea.html:478-479; スナップショット haml:249-250 は short.q 表記) / 新: views/enrichment_analysis.erb:133, `curl -I` 結果 (job_queue_status → 200, GridEngine → 404)
- **確認方法**: `curl+ソース確認済み`

---

## F. 入力バリデーション

### EA-27 タイトル欄の文字種チェックが無い
- **ページ/機能**: Enrichment Analysis > 送信時の検証 (Analysis title / Dataset A title / Dataset B title / TSS 距離)
- **旧 (chip-atlas.org)**: 送信前に `evaluateText()` が英数字・空白・`_` `.` `-` 以外を含むと `alert("Invalid characters are detected in Project title. Acceptable characters are:\n- alphanumerics (abcABC123)\n- space ( )\n- underscore (_)\n- period (.)\n- hyphen (-)")` で中断 (User data title / Compared data title も同様)。TSS 距離は数字以外を拒否 (`- positive integer (1,2,3,..)`)。
- **新 (localhost:9292)**: 検証なし。タイトルに `&`, `/`, 日本語などを入れてもそのまま WABI に送られる。残っている `Analysis title` の ⓘ は「Acceptable letters are alphanumeric …」と案内したまま。TSS 距離は `type=number` のブラウザ制約のみ。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:639-689 / 新: frontend/pages/enrichment-analysis.ts:748-791 (検証は空チェックのみ)
- **確認方法**: `ソース推定`
- **備考**: WABI が生成する結果 HTML のタイトル表示や TSV の列名に影響する可能性 (未検証)。

### EA-28 BED/遺伝子リスト本文の文字置換が無い
- **ページ/機能**: Enrichment Analysis > 送信時の本文整形
- **旧 (chip-atlas.org)**: `replaceDataChars()` が `bedAFile`/`bedBFile` の `[^a-zA-Z0-9\t_\n]` を全て `_` に置換して送る (例: `chr1:100-200` → `chr1_100_200`、`ENSG00000204531.1` → `ENSG00000204531_1`、CSV の `,` も `_`)。
- **新 (localhost:9292)**: 原文のまま送る (サーバ側 WabiService も利用者フィールドは加工しない)。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:691-695, 763 / 新: frontend/pages/enrichment-analysis.ts:594-623, lib/services/wabi_service.rb:151-153, test/services/wabi_service_test.rb:27
- **確認方法**: `ソース推定`
- **備考**: 旧では「CSV or TSV」と案内しつつ CSV のカンマを `_` にしていたので、CSV カウント表は本番では実質壊れていた可能性がある (新版は改善方向)。一方で記号を含む BED 4 列目以降や版付き ID を WABI がどう扱うかは未検証。

### EA-29 空の dataset A の検出
- **ページ/機能**: Enrichment Analysis > 送信時
- **旧 (chip-atlas.org)**: 空欄でも検証を通り (bed 用 regexp は `/.*/`)、`bedAFile=""` で WABI に投入される。
- **新 (localhost:9292)**: 空欄 (空白のみ含む) なら `Dataset A is empty.` を表示して送信しない。ファセット未読込なら `Filter not ready yet.`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:671-689 / 新: frontend/pages/enrichment-analysis.ts:750-755
- **確認方法**: `ソース推定`
- **備考**: 行数上限・ファイルサイズ上限・座標形式チェック・遺伝子記号の大文字小文字正規化は旧新ともに無い (差分なし)。

---

## G. ジョブ投入

### EA-30 送信経路と運用フィールドの付与
- **ページ/機能**: Enrichment Analysis > 送信リクエスト
- **旧 (chip-atlas.org)**: ブラウザが `address=""`, `format=text`, `result=www` を含む form データを `POST /wabi_chipatlas` に送り、サーバが WABI へ `post_form`。サーバは直前に `wabi_endpoint_status` が `chipatlas` でなければ 503。
- **新 (localhost:9292)**: ブラウザは `POST /jobs/submit` に JSON `{type:"enrichment_analysis", params:{…}}` を送る。`address/format/result/sbatchOptions` はサーバ (WabiService) が付与。フィールド名 (`genome, antigenClass, cellClass, threshold, typeA, bedAFile, typeB, bedBFile, permTime, title, descriptionA, descriptionB, distanceUp, distanceDown`) は本番と同一。閾値の符号化 ("05"→"50") も本番と一致。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:581-625, 758-803, old-app/app.rb:477-501 / 新: frontend/api/client.ts:410-416, routes/jobs.rb:51-75, lib/services/wabi_service.rb:19-24, 151-153, frontend/pages/enrichment-analysis.test.ts:88-121
- **確認方法**: `ソース推定` (JSON 不正 body を送って 400 `{"error":"Invalid JSON"}` になることのみ curl 確認可、実投入はしていない)
- **備考**: 不正な JSON は lib/middleware/json_body_parser.rb:22-27 で 400、JSON body 無しは app.rb:49-54 で 400。それ以外の検証は無く、`params` が空でも WABI に送られる (API 利用者向けの注意点)。

### EA-31 `sbatchOptions="-p epyc -t 180"` が全ジョブに付く
- **ページ/機能**: Enrichment Analysis > 送信パラメータ
- **旧 (chip-atlas.org)**: `antigenClass == "Bisulfite-Seq"` のときだけ `sbatchOptions: "-p epyc -t 180"` を付ける。他は付けない (WABI 既定のキュー・時間制限)。
- **新 (localhost:9292)**: 実験タイプに関わらず常に `-p epyc -t 180` を付与。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:621-623 / 新: lib/services/wabi_service.rb:19-24
- **確認方法**: `ソース推定`
- **備考**: 本番ページの表記は全て「epyc.q」なので既定キューは同じ可能性が高いが、`-t 180` (180 分制限) が非 Bisulfite ジョブの上限を変えるかは WABI 側の既定値に依存し未確認。オーナー確認事項。

### EA-32 `permTime` の送信条件
- **ページ/機能**: Enrichment Analysis > 送信パラメータ
- **旧 (chip-atlas.org)**: 常に送信 (未選択なら 1)。
- **新 (localhost:9292)**: B が Random permutation のときだけ送信。BED/Refseq/Gene list/Count では省略。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:583-586, 605 / 新: frontend/pages/enrichment-analysis.ts:615, frontend/pages/enrichment-analysis.test.ts:174-180
- **確認方法**: `ソース推定`
- **備考**: WABI が `permTime` 必須かどうかは未確認。本番と同じく常に送る方が安全。

### EA-33 送信失敗時のメッセージ
- **ページ/機能**: Enrichment Analysis > 送信エラー
- **旧 (chip-atlas.org)**: `alert("Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." + JSON.stringify(response))`。
- **新 (localhost:9292)**: ボタン下に `Submit failed. Try again or check the service status.`。サーバの 503 `No compute backend available` / 502 `Compute backend rejected the submission` の区別は表示されない。「service status」への導線も無い。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:786-793 / 新: frontend/pages/enrichment-analysis.ts:787-790, routes/jobs.rb:60-63
- **確認方法**: `ソース推定`

### EA-34 結果ページへの遷移 URL
- **ページ/機能**: Enrichment Analysis > 送信成功後のリダイレクト
- **旧 (chip-atlas.org)**: `/enrichment_analysis_result?id=<requestId>&api=wabi&title=<タイトルを未エンコード連結>&calcm=<推定文字列からハイフンを除去>`。結果ページ側は query 全体を decodeURIComponent してから `&`/`=` で分割するため、タイトルに `&` や `=` があると壊れる。
- **新 (localhost:9292)**: `/enrichment_analysis_result?id=…&backend=wabi&title=<encodeURIComponent>&calcm=<encodeURIComponent>`。`URLSearchParams` で読むので `&`/`=` を含むタイトルも往復できる。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:773-784, old-app/public/js/pj/enrichment_analysis_result.js:52-62 / 新: frontend/pages/enrichment-analysis.ts:782-786, frontend/components/result-page-params.ts:32-43, frontend/components/job-tracker.test.ts:176-180
- **確認方法**: `ソース推定`
- **備考**: エンコードは改良。パラメータ名の変更による旧 URL 非互換は EA-38。

### EA-35 POST プリフィルで `taxonomy` が無視される (ゲノムタブが切り替わらない)
- **ページ/機能**: `POST /enrichment_analysis` (外部サービスからの遺伝子リスト受け渡し)
- **旧 (chip-atlas.org)**: `taxonomy` (taxid) があれば `taxidMap` で種の先頭アセンブリ (9606→hg19, 10090→mm9, 10116→rn6, 7227→dm3, 6239→ce10, 4932→sacCer3) のタブを表示し、`genes` があれば Gene list モードで A に投入、`genesetA`+`genesetB` なら A/B とも Gene list で投入。
- **新 (localhost:9292)**: `genes` / `genesetA`+`genesetB` の扱い (Gene list + Refseq / Gene list + Gene list) は同等だが、`taxonomy` は `PageData` に受け取るだけで一切参照されず、タブは hg38 (またはハッシュのゲノム) のまま。マウス遺伝子が hg38 タブに入る。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:31-62, 228-255, old-app/app.rb:337-353 / 新: routes/pages.rb:90-99, views/enrichment_analysis.erb:6-14, frontend/pages/enrichment-analysis.ts:17-25 (宣言のみ), 205-219, 719-725
- **確認方法**: `ソース推定`
- **備考**: 旧の対応表は hg19/mm9/dm3/ce10 を選ぶため、新版では 9606→hg38, 10090→mm10, 7227→dm6, 6239→ce11, 3702→TAIR12 に読み替える必要がある。呼び出し元は両アプリ内には無く外部サービスと推定 (未確認)。

---

## H. バックエンド可用性

### EA-36 ページ読込時の WABI 死活確認・ボタン無効化・警告が無い
- **ページ/機能**: Enrichment Analysis > 読込時
- **旧 (chip-atlas.org)**: `GET /wabi_endpoint_status` (WABI トップの本文、現在 `chipatlas`) が `chipatlas` でなければ submit ボタンを `disabled` にし、`alert("Enrichment analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.")` を出す。
- **新 (localhost:9292)**: 読込時の確認は無い。`GET /jobs/available?type=enrichment_analysis` (現在 `{"backend":"wabi","available":true}`) と `GET /status` (`enrichment_analysis: "ok"` / `"ok (backup)"` / `"unavailable"`) は用意されているが、enrichment-analysis.ts はどちらも呼ばない (diff-analysis.ts:248 は `checkJobAvailability` を呼ぶ)。停止中は送信して初めて `Submit failed. Try again or check the service status.` になる。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:112-127, old-app/app.rb:30-38, 455-457, curl `https://chip-atlas.org/wabi_endpoint_status` → `chipatlas` / 新: `grep checkJobAvailability frontend/pages/enrichment-analysis.ts` 該当なし, routes/jobs.rb:45-48, lib/services/service_monitor.rb:38-63, 87-91, curl `/jobs/available`, `/status`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的な削除の記録は見当たらない。Diff Analysis と同じ `checkJobAvailability` 呼び出しをこのページにも入れるのが自然。

### EA-37 WES (ea.chip-atlas.org) フォールバック
- **ページ/機能**: Enrichment Analysis > バックエンド選択
- **旧 (chip-atlas.org)**: `sapporoService` 定数はコメントアウトされており WABI 固定 (Sapporo 経路のコードは残存するが到達しない)。
- **新 (localhost:9292)**: WABI 不通時に WES (`https://ea.chip-atlas.org/runs`) へ自動フォールバック。利用者には結果 URL の `backend=wes` と、結果リンクが `https://chip-atlas.dbcls.jp/data/enrichment-analysis/<id>/<id>.result.html|.tsv` になることで見える。現在 `/status` は `wes: "not_checked"`、`/jobs/…?backend=wes` は 503 (WES down 判定)。
- **分類**: `新機能`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis.js:2-3, 705-756 / 新: lib/services/compute_router.rb:21-24, 29-39, 50-60, 87-92, lib/services/sapporo_service.rb:14-78, curl `/status`, `/jobs/fakeid123/status?backend=wes`
- **確認方法**: `curl+ソース確認済み`
- **備考**: WES の状態語 `canceled` は job-tracker の終了集合 (finished/completed/success, error/failed/backend_unavailable) に含まれず、永久にポーリングし続ける (job-tracker.ts:19-20, sapporo_service.rb:45-52)。旧 Sapporo 経路は `permTime/threshold/distance` を整数化して送っていたが新は文字列のまま (WES 側の型要件は未確認)。

---

## I. 結果ページ

### EA-38 旧 URL 形式 (`api=wabi`) が新版で開けない
- **ページ/機能**: `/enrichment_analysis_result` > URL パラメータ
- **旧 (chip-atlas.org)**: `?id=…&api=wabi&title=…&calcm=…`。
- **新 (localhost:9292)**: `?id=…&backend=wabi&title=…&calcm=…`。`backend` が無いと `Missing id or backend parameter in URL.` の赤いアラートを出し、表を隠す。本番でブックマークした URL (有効期間 1 週間) を新版で開くとこの状態になる。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:23-50 / 新: frontend/components/result-page-params.ts:32-43, frontend/pages/enrichment-result.ts:11-20
- **確認方法**: `ソース推定` (要ブラウザ確認)
- **備考**: `api=wabi` を `backend=wabi` の別名として受け、それ以外の `api=<host>` を `wes` と読むだけで互換になる。

### EA-39 id/backend/title 欠落時の表示
- **ページ/機能**: `/enrichment_analysis_result` > 異常 URL
- **旧 (chip-atlas.org)**: パラメータが無いと各セルに `undefined` が入り、`api` が無いと `https://undefined/runs/undefined/status` を 10 秒ごとに叩き続ける。Status は `Requesting` のまま。
- **新 (localhost:9292)**: `Missing id or backend parameter in URL.` を表示して停止。`title` が無ければ `—`、`calcm` が無ければ Estimated finishing time は `—`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:9-20, 137-157 / 新: frontend/pages/enrichment-result.ts:11-20, frontend/components/job-tracker.ts:294-301
- **確認方法**: `ソース推定`

### EA-40 ポーリングと状態語
- **ページ/機能**: `/enrichment_analysis_result` > Status
- **旧 (chip-atlas.org)**: 10 秒間隔で `GET /wabi_chipatlas?id=` を呼び、サーバは WABI の結果 HTML (`?info=result&format=html`) を取得して 200 なら `finished`、それ以外は `running`、ping 失敗なら `server unavailable` を返す。未知 ID でも `running` のまま (本番で `id=fakeid123` → `running` を確認)。`finished` で停止。
- **新 (localhost:9292)**: 10 秒間隔で `GET /jobs/:id/status?backend=`。サーバは WABI の `?info=status` の `status:` 行をそのまま返し、取れなければ `unknown` (`fakeid123` → `unknown` を確認)。`finished/completed/success` で成功停止、`error/failed/backend_unavailable` で失敗停止、それ以外 (`running`, `unknown`, `queued` 等) は継続。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:117-158, old-app/app.rb:459-474, curl `https://chip-atlas.org/wabi_chipatlas?id=fakeid123` / 新: frontend/components/job-tracker.ts:16-20, 201-225, routes/jobs.rb:78-91, lib/services/wabi_service.rb:97-137, curl `/jobs/fakeid123/status?backend=wabi`
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新は結果 HTML を毎回取得しないので WABI への負荷は軽い。WABI が返しうる状態語の全体は未確認。

### EA-41 バックエンド停止時に結果ページが何も伝えない
- **ページ/機能**: `/enrichment_analysis_result` > WABI 不通時
- **旧 (chip-atlas.org)**: Status セルに `server unavailable` が表示される (JS は `"unavailable"` と比較して alert「No response from the DDBJ supercomputer system: please note the result URL to access later. …」を出す設計だが、サーバ文字列は `server unavailable` なので一致せず alert は出ない。ポーリングは継続)。
- **新 (localhost:9292)**: `/jobs/:id/status` が 503 `{"status":"backend_unavailable","retry":false}` を返すが、`request()` が非 2xx で例外を投げるため `setStatus` に届かず、`console.warn` して 10 秒後に再試行するだけ。Status セルは直前の語 (初期は `Requesting`) のまま。`backend_unavailable` の失敗表示 (job-tracker.ts:20) は到達不能。結果 URL セルは空、ログ欄は `Log file not available yet. This page refreshes on its own.`。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:122-135, old-app/app.rb:464-473 / 新: routes/jobs.rb:82-87, frontend/api/client.ts:212-219, frontend/components/job-tracker.ts:201-225 (221-224), 163-171, 257-267; curl `/jobs/fakeid123/status?backend=wes` → 503 で再現
- **確認方法**: `curl+ソース確認済み` (画面挙動は要ブラウザ確認)
- **備考**: 503 の JSON を読んで `backend_unavailable` をセルに出す (retry:false なら停止) ようにすれば設計意図どおりになる。

### EA-42 「Submitted at」の算出
- **ページ/機能**: `/enrichment_analysis_result` > Submitted at
- **旧 (chip-atlas.org)**: ページ読込時刻 (`new Date()`) を `HH:MM:SS (Mon-DD-YYYY) / UTC: …` で表示。1 時間後に同じ URL を開き直すと「開き直した時刻」が投入時刻として出る。
- **新 (localhost:9292)**: WABI の requestId (`wabi_chipatlas_YYYY-MMDD-HHMM-SS-…`, JST) から投入時刻を復元して同じ書式で表示。WES の UUID など形式が違う場合は本番同様に読込時刻。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:64-85 / 新: frontend/components/job-tracker.ts:54-61, 80-86, 297-298, frontend/components/job-tracker.test.ts:34-69
- **確認方法**: `ソース推定`

### EA-43 「Estimated finishing time」の欠落時表示
- **ページ/機能**: `/enrichment_analysis_result` > Estimated finishing time
- **旧 (chip-atlas.org)**: `calcm` が `13 mins` / `1.6 hr` 形式なら投入時刻 + 推定。推定が `-` だった場合は送信側でハイフンが除去され空文字で届き、どの分岐にも入らず `Invalid Date` と表示される。
- **新 (localhost:9292)**: 同形式なら投入時刻 (EA-42) + 推定。解釈できなければ `—`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:87-107, old-app/public/js/pj/enrichment_analysis.js:773-775 / 新: frontend/components/job-tracker.ts:104-118, 300-301
- **確認方法**: `ソース推定`

### EA-44 Result URL / Download TSV の提示方法
- **ページ/機能**: `/enrichment_analysis_result` > Result URL, Download TSV
- **旧 (chip-atlas.org)**: 読込直後にクライアント側で組み立てた `https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/<id>?info=result&format=html` / `…&format=tsv` を文字列として表示し、`finished` になったら同じ URL を href に付ける (同一タブで開く)。バックエンド停止中でも URL 文字列は見える。
- **新 (localhost:9292)**: 読込直後に `GET /jobs/:id/result?backend=&type=enrichment_analysis` で URL を取得して文字列表示 (灰色)、終了時に href + `target=_blank` + `rel=noopener` を付ける。URL 文字列は本番と同一 (curl で確認)。バックエンド停止中 (503) は取得できず空欄。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:9-20, 30-33, 160-163 / 新: frontend/components/job-tracker.ts:149-171, 308, public/css/style.css:686-688, curl `/jobs/fakeid123/result?backend=wabi`
- **確認方法**: `curl+ソース確認済み`
- **備考**: ページ冒頭の「Result page URL will be available for a week…」に従って URL を控える運用は、停止中は新版では出来ない (EA-41 と併せて修正)。結果 HTML は両者とも埋め込まず外部リンク。

### EA-45 Status セルの色
- **ページ/機能**: `/enrichment_analysis_result` > Status
- **旧 (chip-atlas.org)**: `finished` で赤字。
- **新 (localhost:9292)**: `finished` 等で緑太字 (`text-success`)、失敗語で赤太字 (`text-danger`)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:125-128 / 新: frontend/components/job-tracker.ts:173-184
- **確認方法**: `ソース推定`

### EA-46 結果ページの文言差
- **ページ/機能**: `/enrichment_analysis_result` > 見出し・表ラベル
- **旧 (chip-atlas.org)**: リード `identify common epigenetic features of a given set of genomic loci and genes` (小文字始まり、ピリオド無し)。表ラベル `Project title` / `Request ID` / `Submitted at:` / `Estimated finishing time:` / `Current time:` / `Status` / `Result URL:` / `Download TSV:` (一部コロン付き、td)。末尾文 `… Please check computation node status here (epyc.q)`。
- **新 (localhost:9292)**: リード `Identify … genes.`。表ラベルはコロン無しで `<th scope="row">` (太字)。末尾文は `… here (epyc.q).` (ピリオド追加)。冒頭文 `Result page URL will be available for a week from the time when 'status' is 'finished'.` と初期 Status `Requesting`、`<title>` `ChIP-Atlas: Enrichment Analysis Result` は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: 本番 HTML (old-ea-result.html), old-app/views/enrichment_analysis_result.haml:27-80 / 新: views/enrichment_analysis_result.erb:7-48, curl 結果
- **確認方法**: `curl+ソース確認済み`

---

## J. ログ表示

### EA-47 ログの取得・停止・描画方法
- **ページ/機能**: `/enrichment_analysis_result` > Execution Log
- **旧 (chip-atlas.org)**: `GET /enrichment_analysis_log?id=` (サーバが WABI `?info=result&format=log` を中継、content-type 既定の text/html) を読込直後と 10 秒ごとに、ジョブ終了後も無期限に取得。本文は `.html("<h3>Execution Log</h3><pre><code>" + log + "</code></pre>")` で挿入するため、ログ中の `<` 等が HTML として解釈される。
- **新 (localhost:9292)**: `GET /jobs/:id/log?backend=` (text/plain) を同じ 10 秒間隔で取得し、Status が終了語になったら最後に 1 回読んで停止。`textContent` で挿入 (HTML 解釈なし)。`<pre>` は `max-height:400px` でスクロール。見出し `Execution Log` は同じ。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:171-207, old-app/app.rb:383-390 / 新: frontend/components/job-tracker.ts:206-220, 227-244, 269-278, routes/jobs.rb:107-122, lib/services/wabi_service.rb:139-149
- **確認方法**: `ソース推定` (ログ内容の同一性は実ジョブ無しのため未確認)
- **備考**: UI から直接ログ URL へ行く導線は両者とも無い (ページ内に埋め込むのみ)。`/jobs/:id/log` の 404 本文は not_found ハンドラにより HTML の 404 ページになる (`halt 404, 'Log not available yet'` の文字列は届かない)。旧 `/enrichment_analysis_log` も同様に HTML 404 ページ (curl で両方確認)。フロントは status のみ見るので画面上の影響は無い。

### EA-48 ログ未取得時の文言
- **ページ/機能**: `/enrichment_analysis_result` > Execution Log のプレースホルダ
- **旧 (chip-atlas.org)**: 404 のとき `Log file not available yet. Please wait...`、それ以外の失敗で `Fetching log file… The page will refresh automatically.` (いずれも欄が空のときだけ)。
- **新 (localhost:9292)**: 200 で空本文のとき `Log file not available yet. Please wait…`、404/503/通信失敗など全ての失敗で `Log file not available yet. This page refreshes on its own.`。既にログがあれば置き換えない。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js:179-199 / 新: frontend/components/job-tracker.ts:246-267
- **確認方法**: `ソース推定`

---

## K. 再訪・ディープリンク

### EA-49 結果ページ再訪の仕組み
- **ページ/機能**: `/enrichment_analysis_result` > ブックマーク
- **旧 (chip-atlas.org)**: 必要な情報 (id, api, title, calcm) は全て URL に載る。localStorage 等は使わない。再訪時に Status を再取得できるが Submitted at は狂う (EA-42)。
- **新 (localhost:9292)**: 同じく URL のみ (id, backend, title, calcm)。localStorage 不使用。セットアップページ側は `#genome=` ハッシュでゲノムを共有できる (EA-02)。旧 URL 形式との非互換は EA-38。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/public/js/pj/enrichment_analysis_result.js 全体 / 新: frontend/components/result-page-params.ts, frontend/components/job-tracker.ts (storage 呼び出し無し)
- **確認方法**: `ソース推定`

---

## 差分なしと確認できた事項 (参考)
- パネル見出し 1〜6 の文言 (`1. Experiment type` … `6. Analysis description`)、`Analysis title` / `Dataset A title` / `Dataset B title` と初期値 `My project` / `Dataset A` / `Dataset B`、`Choose local file` (A 側)、`Try with example` (A 側) の文言。
- 閾値ラベル 50/100/200/500 と既定 50、ファイルコード→WABI threshold の変換 ("05"→"50" … "50"→"500")。
- 実験タイプ 7 件のラベルと件数、細胞型クラスの語彙 (`Unclassified`, `No description`, `Others` を含む) と件数 (hg38 で照合)。
- 推定実行時間の式・定数・参照データ (共通キー 2,895 件で値の差 0)、既定表示 `13 mins`。
- example ファイル (hg38 等 10 ゲノム分) の内容。
- WABI 送信フィールド名、結果 URL の形式、ポーリング間隔 10 秒、`Result page URL will be available for a week …` の文言、Tutorial の 3 リンク。
- 行数上限・ファイルサイズ上限・座標書式検査・遺伝子記号の大文字小文字処理: 旧新ともに無し。

---

## 要ブラウザ確認リスト
1. Tutorial ボタンの位置 (h1 右横に並ぶか、タブ下に落ちるか) と、`.list-box` (size 8) の閾値ボックスの見た目 (EA-05, EA-09)。
2. ⓘ popover の改行が潰れるか、`focus click` トリガでキーボード操作で開閉できるか、複数の popover が同時に開かないか (EA-21)。
3. ゲノムタブ切替で textarea・モード・タイトル・TSS 距離が保持されること (EA-03)。
4. Gene count table 選択時のパネル 5/6 の表示 (Random permutation と ×1/×10/×100 が残る、タイトル欄が残る) (EA-15)。
5. Gene list / Count モードで「Try with example」を押すと BED に戻って bedA が入ること、TAIR12 タブで `Failed to load example data.` になること (EA-12, EA-13)。
6. Bisulfite-Seq 選択時に閾値リストが 50/100/200/500 のままであること (EA-08)。
7. 読込直後の `Estimated run time: 13 mins` と、textarea 入力・permutation 変更での更新、gene+rnd での `—` (EA-25, EA-14)。
8. dataset B の textarea/file の hidden 切替と補足文 (`Random permutation needs no input.` 等) (EA-14)。
9. 旧形式 URL `/enrichment_analysis_result?id=X&api=wabi&title=T&calcm=13%20mins` を新版で開いたときの `Missing id or backend parameter in URL.` (EA-38)。
10. 結果ページで `/jobs/:id/status` が 503 の場合に Status が更新されないこと (WES 経路 `backend=wes` で再現可能: `?id=any&backend=wes`) (EA-41)。
11. Submit の二重クリックで 2 回送信されること (EA-24) — 実ジョブが WABI に投入されるため、WABI をスタブした環境 (`WabiService.poster=`) でのみ検証すること。
12. 細胞型を変えたときに実験タイプの件数が更新されること (EA-07)。

## 未確認・不確実事項
1. WABI 側の受け入れ仕様は実ジョブを投入していないため未検証: カウント表での `typeB=rnd` (EA-16)、`permTime` 省略 (EA-32)、Bisulfite-Seq での `threshold=50` (EA-08)、全ジョブへの `sbatchOptions="-p epyc -t 180"` (EA-31)、記号を含む本文・タイトルの原文送信 (EA-27, EA-28)、`gene + rnd` / `gene + bed` の組合せ (EA-14)。
2. WABI `?info=status` が返す状態語の全体 (`finished`/`running` 以外に何があるか) は未確認 (EA-40)。
3. `POST /enrichment_analysis` に `taxonomy` を付けて呼ぶ外部サービスの有無・数は不明 (両アプリ内には呼び出し元が無い) (EA-35)。
4. `SCR/old-app` スナップショットの HAML は `node status (short.q)` だが本番配信 HTML は `(epyc.q)` であり、本番はスナップショットより新しい可能性がある。文言比較は本番 HTML を正としたが、JS 以外のビューにも他の差がある可能性は残る。
5. popover の改行の見え方 (EA-21) と Tutorial ボタンの位置 (EA-05) は CSS/ERB からの推定。
6. WES (ea.chip-atlas.org) は本セッション中 `not_checked`/503 で、フォールバック経路 (EA-37) の実動作は未確認。
7. dataset B 側の「Try with example」「Choose local file」の欠落 (EA-17) が意図的かどうかは記録が見つからない。
8. 結果ページのログ内容 (WABI `format=log`) が旧新で同一に見えるかは実ジョブ無しのため未確認 (取得元 URL は同一)。
9. CUT&Tag / CUT&RUN は両アプリのメニューに無い。BRIEF の「追加」と lib/models/experiment.rb:14-20 の「メニューには出さない」決定のどちらが最終方針かはオーナー確認事項 (EA-06)。
