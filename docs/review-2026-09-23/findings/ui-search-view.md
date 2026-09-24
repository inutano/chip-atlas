# SV: Dataset Search ページ / 実験詳細ページ (/view) の新旧比較

## 担当範囲の要約

- 対象: (A) `/search` (Dataset Search)、(B) `/view?id=...` (実験詳細)、および navbar の「ID → Go」ジャンプのうち /view に着地する部分。旧 = https://chip-atlas.org (GET のみ)、新 = http://localhost:9292。
- 旧 Search は **DataTables が `/data/ExperimentList.json` (44.1 MB) と `/data/ExperimentList_adv.json` (161.6 MB) を毎回両方ダウンロード**してクライアント側で部分文字列フィルタする方式。旧 `/data/search` (サーバ側 FTS5) は UI からは使われていない。新は `/api/search` (FTS5、20 件ずつサーバページング)。ページ表示は桁違いに軽くなった一方、**検索の意味論が「部分文字列 AND」から「トークン完全一致 AND (前方一致なし)」に変わり**、`H3K4`/`SRX0186`/`NFkB` のような入力で旧より大幅に少ない (または 0 件の) 結果になる。列ソート・表示件数変更・全件エクスポートは無くなった。
- 「検索結果の Title に `GSM####:` 接頭辞」は **旧版にも無い** (本番 JSON 432,319 行中 0 行)。/view の見出し下のタイトルには新旧とも接頭辞が付く。
- /view は見出し・セクション構成・文言がほぼ同一。差分は hg19 セクション消滅 (意図的)、IGV 到達確認の追加、Comparative Profile のヘルプ (ⓘ)/ローディング表示/拡大モーダルの削除、「Where can I get the processing logs?」リンクの削除、"CellType:"→"Cell Type:" など。
- **退行 (要修正) 3 件**: (1) Bisulfite-Seq 実験でも Analyze メニューが表示される (旧は非表示)、(2) NCBI 取得失敗の結果 (ERROR 文言) も 30 日キャッシュされる、(3) 相関 TSV の URL 生成規則が旧と異なり、`+ . , / ( )` 等を含む細胞種/抗原 (本番実験の 5.8%、例: CD4+ T cells) で TSV が 404 になりリンクが出ない。
- NCBI メタデータは初回のみ同期取得 (約 0.9–1.0 秒、本番と同程度) で以後キャッシュ (4 ms)。本番は毎回 NCBI に問い合わせる (計測 1.04 秒)。
- 作業中、ローカル DB (`database.sqlite.verify`, bind mount + WAL) にホスト側 `sqlite3` CLI で同時アクセスした時間帯に新版が `SQLite3::IOException: disk I/O error` (500) を返し、その後 14:18:13 UTC に sqlite3 拡張内の `Bus Error` (SIGBUS) で **コンテナが落ちた**ため `docker start chip-atlas-local` で再起動した (14:21 UTC)。詳細は末尾「未確認・不確実事項」。
- 件数: 改良 11 / 単なる変更 26 / 機能削除 6 / 退行 (要修正) 3 / データ差分 3 / 新機能 1 (計 50 項目)。

---

## (A) Dataset Search

### SV-01 データ読み込み方式: 206 MB の JSON 2 本 → 20 行の API
- **ページ/機能**: Dataset Search > ページ表示
- **旧 (chip-atlas.org)**: ページ表示時に Simple/Detailed 両タブの DataTables が同時に初期化され (`simpleSearch(); DetailedSearch();`)、`/data/ExperimentList.json` (44,110,965 bytes) と `/data/ExperimentList_adv.json` (161,647,706 bytes) を**毎回**ダウンロードし、432,319 行をブラウザ内で保持・型判定・フィルタする。サーバ側も毎リクエスト `JSON.dump(settings.experiment_list)` で生成。本環境での取得時間は 1.26 s + 4.61 s (回線が速い場合)。
- **新 (localhost:9292)**: 初期表示で `/api/search?limit=20&offset=0` (約 8 KB) を 1 回呼ぶだけ。
- **分類**: `改良`
- **影響度**: 高
- **根拠**: 旧: old-app/public/js/pj/search.js:48-49, 70, 138; old-app/app.rb:113-145 (`/data/:data.json`), 80-81; curl 計測 (`SCR/sv/fetch.log`)。新: frontend/pages/search.ts:6, 176-190, 246-248; routes/api.rb:94-101
- **確認方法**: `curl+ソース確認済み` (ブラウザ上の実所要時間・メモリは要ブラウザ確認)
- **備考**: 旧はスマホ・低速回線ではほぼ使えないレベルの転送量。

### SV-02 見出し下リード文の文言
- **ページ/機能**: Dataset Search > ヘッダ
- **旧**: 2 段落。「Find experiments by keywords」/「Available track type classes, cell type classes, and reference genomes are the same as in the Peak Browser. For bulk processing, please use the metadata table」
- **新**: 1 段落。「Find experiments by keywords. Same track type classes, cell type classes, and reference genomes as the Peak Browser. For bulk processing, see the metadata table.」
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/search.haml:35-41 / 新: views/search.erb:6-14; curl 本文 (`SCR/sv/prod-search.txt`, `new-search.txt`)
- **確認方法**: `curl+ソース確認済み`

### SV-03 「metadata table」リンクが新規タブで開く
- **ページ/機能**: Dataset Search > ヘッダ
- **旧**: 同一タブ (`target` なし)
- **新**: `target="_blank" rel="noopener noreferrer"`
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/search.haml:41 / 新: views/search.erb:10
- **確認方法**: `curl+ソース確認済み`

### SV-04 Simple / Detailed タブの廃止、Title・Attributes 列の常時表示
- **ページ/機能**: Dataset Search > 表
- **旧**: 「Simple search」(既定、8 列: SRX ID/SRA ID/GEO ID/Genome/Track type class/Track type/Cell type class/Cell type) と「Detailed search」(10 列: +Title/Attributes) の 2 タブ。既定では Title/Attributes は見えない。
- **新**: タブ無し、常に 10 列 (SRX/SRA/GEO/Genome/Track class/Track type/Cell type class/Cell type/Title/Attributes)。Title/Attributes セルは `max-width: 320px`、表全体は `table-responsive` で横スクロール。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: old-app/views/search.haml:53-65, search.js:71-115, 139-197 / 新: views/search.erb:41-59; public/css/style.css:228-231; docs/ui-parity-audit-2026-09-14.md:175-178, 239 (「タブは戻さない」判断)
- **確認方法**: `curl+ソース確認済み` (横幅・折り返しの見え方は要ブラウザ確認)
- **備考**: 意図的 (commit 0914944 "D1")。狭い画面では横スクロールが発生し得る。

### SV-05 列見出しの文言変更とツールチップ削除
- **ページ/機能**: Dataset Search > 表ヘッダ
- **旧**: 「SRX ID」「SRA ID」「GEO ID」「Genome」「Track type class」「Track type」「Cell type class」「Cell type」「Title」「Attributes」。各見出しに `title` ツールチップ (例: "Experimental ID." / "Accession ID" / "Experimental ID in GEO" / "Genome assembly (hg19, mm9, rn6, dm3, ce10, sacCer3)" / "Track type class name including curated antigen class" / "Curated cell type class" / "Title written by authors" / "Attributes written by authors")。
- **新**: 「SRX」「SRA」「GEO」「Genome」「Track class」「Track type」「Cell type class」「Cell type」「Title」「Attributes」。ツールチップ無し。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: search.js:73-114, 141-196 / 新: views/search.erb:45-54
- **確認方法**: `curl+ソース確認済み`
- **備考**: 旧のツールチップ文は列の意味 (curated かどうか) を説明していたので、新でも `title` か凡例で補うとよい。

### SV-06 検索ボックスの操作モデル: 逐次フィルタ → 送信型
- **ページ/機能**: Dataset Search > 検索入力
- **旧**: DataTables 標準の「Search:」ラベル付き入力。1 キー入力ごとに全 432,319 行を即時フィルタ (送信操作不要)。タブごとに独立した検索欄。
- **新**: プレースホルダ「e.g. K562 H3K4me3」の `<input type="search">` + ゲノム `<select>` + 「Search」ボタン。Enter/ボタン押下で `/api/search` を呼ぶ。可視ラベル無し (`aria-label` のみ)。検索中は「Searching…」を表示。
- **分類**: `単なる変更`
- **影響度**: 中
- **根拠**: 旧: dt.js (1.10.16) 既定 `bSmart:true, bCaseInsensitive:true` (`SCR/sv/dt.js:9453-9476`), `sSearch: "Search:"` (dt.js:11660) / 新: views/search.erb:17-29; frontend/pages/search.ts:250-257, 178
- **確認方法**: `curl+ソース確認済み`
- **備考**: サーバ検索なので送信型は妥当。可視ラベルが無くなった点は軽微な a11y 後退。

### SV-07 検索の意味論: 部分文字列 AND → FTS5 トークン完全一致 AND (前方一致なし)
- **ページ/機能**: Dataset Search > 検索結果の一致条件
- **旧**: DataTables smart search。クエリを空白で分割 (二重引用符で囲めば 1 語)、**各語が行内のどこかに部分文字列として含まれる** (大小無視) 行だけ残す。対象は表示中タブの全列 (Simple: 8 列、Detailed: 10 列。Attributes は `key: value` 形式に整形後の文字列)。
- **新**: `fts5_sanitize` がクエリを空白で分割し、各トークンから `" ' ( ) * ^ { } :` を除去して `"token"` に包み、空白結合 (= 暗黙 AND)。FTS5 テーブルは既定 `unicode61` トークナイザ (記号 `- + . / _ , :` などは区切り)。**トークン単位の完全一致**のみで、前方一致 (`*`) は除去されるため使えない。順位は bm25 `rank`。
- **分類**: `単なる変更`
- **影響度**: 高
- **根拠**: 旧: dt.js:4443 (`search.match(/"[^"]+"|[^ ]+/g)`) と 9453-9476 / 新: lib/models/experiment_search.rb:94-124, 150-157; `sqlite3 .schema experiments_fts` (tokenize 指定なし); localhost `/api/search` 実測
- **確認方法**: `curl+ソース確認済み` (旧側は本番 JSON をローカルで DataTables と同じ規則でシミュレーション: `SCR/sv/oldfilter.py`)
- **備考**: 主な実測 (旧 = 本番 JSON 432,319 行に対する Simple タブ / Detailed タブの一致行数、新 = `/api/search` の `total`。新 DB は 453,932 行で TAIR12 を含むため絶対数は完全には比較できない):

  | クエリ | 旧 Simple | 旧 Detailed | 新 | 差の理由 |
  |---|---:|---:|---:|---|
  | `H3K4me3` | 13,366 | 18,592 | 19,170 | ほぼ同等 |
  | `H3K4` | 21,999 | 30,018 | **228** | 新は前方一致しない (`H3K4me3` に当たらない) |
  | `CTCF` | 3,786 | 6,252 | 6,022 | 新は `CTCFL` に当たらない |
  | `SRX0186` | 33 | 33 | **0** | 部分アクセッション不可 |
  | `SRX` / `GSE` | 390,424 / 0 | 390,424 / 888 | **0 / 0** | 同上 |
  | `NFkB` | 110 | 726 | 158 | 旧は `NFKB1`,`NFKBIA` 等にも一致 |
  | `hep` | 4,375 | 7,556 | 3,150 | 旧は `HepG2` にも一致 |
  | `K562 H3K4me3` | 0 | 180 | 180 | curated 名は `K-562` (旧 Simple は不一致) |
  | `HepG2` | 0 | 2,943 | 2,941 | 旧 Simple は Title/Attributes を持たない |
  | `Hep G2` | 2,894 | 2,949 | 2,893 | |
  | `MCF7` / `MCF-7` | 0 / 5,434 | 3,814 / 5,493 | 3,690 / 5,493 | |
  | `CD4` | 6,029 | 12,367 | 9,312 | 旧は `CD40`,`CD45` 等にも一致 |
  | `T cells` | 86,838 | 158,426 | 18,308 | 旧は `t` の部分一致でほぼ全行 |
  | `p53` / `TP53` | 539 / 405 | 2,588 / 698 | 1,595 / 661 | |
  | `sample_name=DRS000203` | 0 | 0 | 1 | 旧は `=` を `: ` に整形して検索 |
  | `K562 OR HepG2` | 0 | 0 | 0 | 両版とも `OR` は演算子でない |
  | `hg19` | 196,907 | 196,907 | 0 | データ差分 (hg19 廃止) |

  ユーザが気付く差: 「途中まで打つと減っていく」体験が無くなり、ID の一部・遺伝子名の語幹 (`H3K4`, `Sox`, `NFkB`) で **0 件または激減**する。改善案: 最後のトークンだけ `"token"*` の前方一致にする、または FTS5 `tokenize='trigram'` (3 文字以上の部分一致) を検討。

### SV-08 特殊文字・記号の扱い
- **ページ/機能**: Dataset Search > 検索入力
- **旧**: 記号もそのまま部分一致 (例: `(` は括弧を含む行に一致)。二重引用符は「1 語扱い」の意味を持つ。
- **新**: `" ' ( ) * ^ { } :` は無視される (`"K562"` = `'K562'` = `K562`、`H3K4me3*` = `H3K4me3`)。記号だけのクエリ (`(` や `*`) は sanitize 後空 → **`total:0`「No entries found」** (全件一覧には戻らない)。ハイフン等は区切りとして扱われるため `ATAC-Seq` ≒ `ATAC Seq` (101,148 vs `ATAC` 101,200)、`NF-kB` は 37 件、`CD4+ T cells` は 6,888 件と自然に動く。`GSM469863:` (コロン付き) も 1 件で一致。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 新: lib/models/experiment_search.rb:97-98, 150-157; `/api/search?q=(` → `{"total":0}` 実測
- **確認方法**: `curl+ソース確認済み`

### SV-09 ゲノム絞り込みセレクタの追加
- **ページ/機能**: Dataset Search > 検索フォーム
- **旧**: 絞り込み UI 無し (検索欄に `hg38` と打つと Genome 列 `hg19, hg38` に部分一致)。
- **新**: 「All genomes」+ `hg38 — H. sapiens (hg38)` … `TAIR12 — A. thaliana (TAIR12)` の 7 択 (`/api/genomes`)。空クエリ + ゲノムでそのゲノムの全件一覧 (`mm10` で 194,020 件)。
- **分類**: `新機能`
- **影響度**: 中
- **根拠**: 新: views/search.erb:21-25; frontend/pages/search.ts:49-62; lib/models/experiment_search.rb:100-118, 126-148; `/api/genomes` 実測
- **確認方法**: `curl+ソース確認済み`

### SV-10 Genome 列の表示値: `hg19, hg38` → `hg38`
- **ページ/機能**: Dataset Search > 表 > Genome 列
- **旧**: 1 実験 1 行で、Genome セルは `hg19, hg38` / `mm9, mm10` / `dm3, dm6` / `ce10, ce11` のような**カンマ区切りの複数アセンブリ**。
- **新**: 1 行 1 アセンブリで `hg38` 等の単一値 (現在は 1 種 1 アセンブリなので行数は実験数と同じ)。
- **分類**: `データ差分`
- **影響度**: 低
- **根拠**: 旧: 本番 JSON 実測 (genome 値の分布: `hg19, hg38` 196,907 / `mm9, mm10` 194,064 / `sacCer3` 16,544 / `dm3, dm6` 14,994 / `ce10, ce11` 6,856 / `rn6` 2,954) / 新: `/api/search` 実測、lib/models/experiment.rb:283-406 (ロード規則)
- **確認方法**: `curl+ソース確認済み`

### SV-11 列ソートの廃止と既定の並び順
- **ページ/機能**: Dataset Search > 表
- **旧**: 全列ヘッダクリックでソート可 (DataTables)。既定は「Cell type class」昇順 (`order: [[6,'asc']]`)。
- **新**: ソート UI 無し。空クエリの一覧は `experiment_id` 昇順 (先頭は `DRX000201`…)、検索時は bm25 関連度順 (`ORDER BY rank`)。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: search.js:116, 198 / 新: lib/models/experiment_search.rb:105, 115, 133, 141; views/search.erb (ソート要素なし)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的 (docs/ui-parity-audit-2026-09-14.md:178「No DataTables, no column sorting, no export」)。関連度順は改良面もある。

### SV-12 「Show N entries」(10/20/50/100) の廃止、固定 20 件
- **ページ/機能**: Dataset Search > 表示件数
- **旧**: 「Show [10|20|50|100] entries」、既定 10。
- **新**: 常に 20 件 (`PAGE_SIZE = 20`)。API 自体は `limit` 1–100 を受け付けるが UI からは変えられない。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: search.js:56-60, dt.js:11580 / 新: frontend/pages/search.ts:6; routes/api.rb:97
- **確認方法**: `curl+ソース確認済み`

### SV-13 件数表示の文言
- **ページ/機能**: Dataset Search > 件数
- **旧**: 「Showing 1 to 10 of 432,319 entries」、フィルタ時は「Showing 1 to 10 of 6,252 entries (filtered from 432,319 total entries)」、0 件時は「Showing 0 to 0 of 0 entries (filtered from …)」+ 表内「No matching records found」。
- **新**: 「Showing 1 to 20 of 453,932 entries」、0 件時は「No entries found」のみ。母数 (filtered from) の表示は無い。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: dt.js:11419, 11440, 11462, 11718 / 新: frontend/pages/search.ts:147-150
- **確認方法**: `curl+ソース確認済み`

### SV-14 ページネーション: 番号付き → Previous / Page x of y / Next
- **ページ/機能**: Dataset Search > ページ送り
- **旧**: DataTables 既定 (1.10 の `simple_numbers`): 「Previous 1 2 3 4 5 … 43232 Next」で任意ページへ直接移動可。
- **新**: 「Previous」「Page 1 of 22697」「Next」。番号ジャンプ無し。ページ数は桁区切り無し (件数側は `toLocaleString`)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: search.js:55 (`dom` に `p`)、DataTables 1.10 既定 / 新: views/search.erb:60-66; frontend/pages/search.ts:152-169
- **確認方法**: `ソース推定` (旧の番号付きページャの描画は要ブラウザ確認)

### SV-15 Copy / TSV エクスポートの範囲: フィルタ結果全件 → 現在ページ 20 行のみ
- **ページ/機能**: Dataset Search > Copy / TSV ボタン
- **旧**: DataTables Buttons `copyHtml5` / `csvHtml5` (タブ区切り `.tsv`)。既定 `modifier: {search:'applied', order:'applied'}` で **現在のフィルタに一致する全行 (全ページ)** を出力 (例: `CTCF` なら 6,252 行、無フィルタなら 432,319 行)。
- **新**: `state.lastResult.experiments` = 表示中の 20 行のみ。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: search.js:61-69, 129-137; `SCR/sv/btn.js:1711-1718` / 新: frontend/pages/search.ts:192-244
- **確認方法**: `curl+ソース確認済み` (旧で 40 万行の Copy が実際に完走するかは要ブラウザ確認)
- **備考**: 意図的 (parity audit「no export」→ 後に現在ページのみ復活)。「一致した数千行を TSV で持ち帰る」用途は新では不可能 (`/api/search?limit=100` を手で回すしかない)。ボタン名が同じなので旧ユーザは範囲の違いに気付きにくい。

### SV-16 TSV / Copy の内容・ファイル名
- **ページ/機能**: Dataset Search > Copy / TSV
- **旧**: 表示中タブの列 (Simple 8 列 / Detailed 10 列) を**表示テキスト**で出力 (HTML 除去、Attributes は `key: value` 形式)。ファイル名は `document.title` 由来「ChIP-Atlas Dataset Search.tsv」(`:` は除去される)。
- **新**: 常に 10 列。ヘッダは `SRX SRA GEO Genome Track class …`。**Attributes は生値のまま** (`sample_name=DRS000203__TAB__strain=C2C12__TAB__…` と内部区切り `__TAB__` がそのまま入る)。ファイル名 `chip-atlas-search.tsv`。値中のタブ/改行のエスケープ無し。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: btn.js:1619-1650 (`_filename`), 1720-1760 (stripHtml) / 新: frontend/pages/search.ts:20-25 (コメントで意図的と明記), 192-202, 239
- **確認方法**: `ソース推定`
- **備考**: `__TAB__` は保存用マーカなので、エクスポートでも画面と同じ ` · ` か `; ` に置換した方が利用者には親切。

### SV-17 Copy 成功時の表示
- **ページ/機能**: Dataset Search > Copy
- **旧**: DataTables Buttons の情報ポップアップ「Copy to clipboard」/「Copied N rows to clipboard」(1 行時「Copied one row to clipboard」)。
- **新**: ボタン文言が 1.5 秒「Copied!」になる。失敗時は console 警告のみで画面表示なし。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: `SCR/sv/btn5.js:835-838` / 新: frontend/pages/search.ts:219-231
- **確認方法**: `ソース推定`

### SV-18 Attributes 列の表示形式 (太字+改行 → 100 字省略+クリック展開)
- **ページ/機能**: Dataset Search > 表 > Attributes (旧は Detailed タブのみ)
- **旧**: `<b>key</b>: value<br><b>key2</b>: value2` — キー太字、1 ペア 1 行、全文表示。
- **新**: `key=value · key2=value2` の 1 行。100 字を超えると先頭 100 字 + `…` の `<summary>` になり、クリックで全文展開 (`<details>`)。マーカー (▶) は CSS で非表示。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: search.js:186-195 / 新: frontend/pages/search.ts:18-25, 80-101; public/css/style.css:228-250
- **確認方法**: `curl+ソース確認済み` (見た目は要ブラウザ確認)
- **備考**: 省略された部分は「クリックできる」ことが視覚的に伝わりにくい (マーカー非表示、色のみ)。

### SV-19 リンクの細部 (SRX / GEO)
- **ページ/機能**: Dataset Search > 表 > SRX 列 / GEO 列
- **旧**: SRX → `/view?id=…` を **新規タブ** (`target='_blank'`)、GEO (`-` 以外) → NCBI GEO `acc.cgi?acc=…` 新規タブ。両方 `title='Open this Info...'` ツールチップ付き。
- **新**: 同じ遷移先・新規タブ。`rel="noopener noreferrer"` 追加、ツールチップ無し、SRX は等幅フォント (`.expid-link`)。GEO は `encodeURIComponent`。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: search.js:73-100, 141-168 / 新: frontend/pages/search.ts:29-32, 64-78, 106-113; style.css:214-221
- **確認方法**: `curl+ソース確認済み`
- **備考**: 依頼文の「旧は同一タブ」は誤り。旧も新規タブだった (commit 7410ce6 のメッセージ "matching production" とも整合)。

### SV-20 読み込み中・エラー時の表示
- **ページ/機能**: Dataset Search > 状態表示
- **旧**: 取得中は表内「Loading...」。JSON 取得失敗時は JavaScript `alert`「DataTables warning: table id=SimpleSearchDataTable - Ajax error. For more information about this error, please see http://datatables.net/tn/7」。
- **新**: 「Searching…」(aria-live)、失敗時は「Search failed. Please try again.」を同じ場所に表示。表は非表示のまま。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: dt.js:11604, 3896, 6441-6447 / 新: frontend/pages/search.ts:176-190; views/search.erb:31
- **確認方法**: `ソース推定`

### SV-21 検索対象データ量の差
- **ページ/機能**: Dataset Search > 母数
- **旧**: 432,319 行 (本番 JSON、2026-09-23 取得)。Annotation tracks は含まれない。
- **新**: 453,932 行 (`experiments_fts`)。内訳: hg38 196,736 / mm10 194,020 / TAIR12 21,833 / sacCer3 16,544 / dm6 14,989 / ce11 6,856 / rn6 2,954。Annotation tracks (544 行) は意図的に除外 (`NOT_INDEXED_TRACK_CLASSES`)。`experiments` 454,476 − 544 = 453,932 で、非 Annotation の全実験が索引されている。
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 旧: `SCR/sv/prod-ExperimentList*.json` 実測 / 新: `/api/search` `/api/stats` 実測; lib/models/experiment_search.rb:19; lib/models/experiment.rb:339-368
- **確認方法**: `curl+ソース確認済み`
- **備考**: 本番 JSON と比べ hg38 −171、mm10 −44、dm6 −5 (スナップショット時期の差か、tab/JSON 交差規則で落ちた行かは未確認)。

### SV-22 外部 CDN 依存の撤廃
- **ページ/機能**: Dataset Search > ページ読み込み
- **旧**: `cdn.datatables.net` (CSS/JS)、`www.datatables.net/.../jquery.js` (jQuery を 2 回読み込み)、`cdnjs.cloudflare.com` (jszip) に依存。CDN 障害時は表が出ない。
- **新**: 同梱 JS/CSS のみ。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/views/search.haml:15-16, 77-81; 本番 HTML の `<script src>` 実測 / 新: views/layout.erb:9-10, 18-21
- **確認方法**: `curl+ソース確認済み`

### SV-23 フォーム部品のアクセシビリティ
- **ページ/機能**: Dataset Search > フォーム/ボタン
- **旧**: DataTables 生成 UI (可視ラベル「Search:」あり)。
- **新**: `role="search"`、`aria-label` 付き入力/セレクト、実 `<button>`、`aria-live="polite"` の状態表示、ページャに `aria-disabled`/`tabIndex` 制御。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 新: views/search.erb:17-31, 60-66; frontend/pages/search.ts:154-169
- **確認方法**: `ソース推定`

---

## (B) 実験詳細ページ /view

### SV-24 hg19 (旧アセンブリ) セクションの消滅
- **ページ/機能**: /view > Visualize / Analyze / Download / Read Processing Pipeline / Experiment Comparative Profile
- **旧**: 各メニュー・各パネルに「For hg38」「For hg19」の 2 ブロック (Read Processing は hg38/hg19 の QC 数値、Comparative Profile は 2 ゲノム分の画像)。
- **新**: hg38 のみ。
- **分類**: `データ差分`
- **影響度**: 中
- **根拠**: 旧: curl 本文 `SCR/sv/prod-view-SRX018625.txt` (For hg19 行), old-app/views/experiment.haml:44-55, 285-321 / 新: `SCR/sv/new-view-SRX018625.txt`; lib/models/experiment.rb:185-191
- **確認方法**: `curl+ソース確認済み`
- **備考**: 意図的 (BRIEF)。hg19 の QC 値・ピーク数 (例: SRX018625 hg19 6,228 peaks) は新では見られない。

### SV-25 Visualize メニュー: 案内ヘッダ/ヘルプ項目の削除と IGV 到達確認の追加
- **ページ/機能**: /view > Visualize
- **旧**: 先頭にヘッダ「Install and launch IGV before selecting data to visualize」、末尾に「Error connecting to IGV?」(クリックで `alert`: 「IGV must be running on your computer before clicking the button. If your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) …」)。項目クリックは `http://localhost:60151/load?...` へそのまま遷移 (IGV 未起動だとブラウザの接続エラー画面に飛ぶ)。
- **新**: ヘッダ/ヘルプ項目なし。項目クリックを横取りして `fetch(localhost:60151/echo, no-cors)` で到達確認。確認中「Contacting IGV…」、未到達なら「Could not reach IGV on localhost:60151. Start IGV on this machine and make sure "Enable port" is on under View › Preferences › Advanced, then try again.」をボタン下に表示してページに留まる。到達時は旧と同じ URL に遷移。
- **分類**: `改良`
- **影響度**: 中
- **根拠**: 旧: experiment.haml:40-41, 79-81; experiment.js:20-21, 116-123 / 新: frontend/pages/experiment.ts:70-116, 270-292; frontend/components/igv.ts:20-42; views/experiment.erb:35
- **確認方法**: `ソース推定` (実 IGV での動作は要ブラウザ確認)
- **備考**: 旧の `title="Click to see visualize options"` (experiment.js:346-352) も無くなった。

### SV-26 IGV 読み込み URL の `name` パラメータのエンコード差
- **ページ/機能**: /view > Visualize > 各項目の URL
- **旧**: `name=HNF4A+%28%40+Hep+G2%29+SRX018625%20(1E-05)` (`URI.encode_www_form_component` = 空白が `+`、その後に `%20(1E-05)` を連結)。
- **新**: `name=HNF4A%20(%40%20Hep%20G2)%20SRX018625%20(1E-05)` (`encodeURIComponent`)。`file`/`genome` は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:46, 51-54; curl 本文 / 新: frontend/pages/experiment.ts:65-68, 80-89
- **確認方法**: `curl+ソース確認済み` (IGV 側でトラック名が同じに復元されるかは要ブラウザ確認)

### SV-27 Bisulfite-Seq 実験でも Analyze メニューが表示される
- **ページ/機能**: /view > Analyze (例: `SRX11233737`, hg38 Bisulfite-Seq)
- **旧**: `div#analyze-dropdown[experiment="Bisulfite-Seq"]` を JS が `hide()` するため Analyze ボタン自体が出ない (Colo/Target Genes は Bisulfite-Seq に存在しない)。
- **新**: Analyze ボタンは常に描画され、Colocalization / Target Genes (TSS ± 1/5/10kb) のリンクが Bisulfite-Seq でも生成される (リンク先は存在しない HTML)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: experiment.js:126-131; 本番 HTML `SCR/sv/prod-view-bs.html:172` (`experiment="Bisulfite-Seq" id="analyze-dropdown"`) / 新: views/experiment.erb:21-24 (無条件描画); frontend/pages/experiment.ts:118-129 (track_class 判定なし); `SCR/sv/new-view-bs.html` に `id="analyze-menu"` と `"track_class":"Bisulfite-Seq"`
- **確認方法**: `curl+ソース確認済み` (旧のボタン非表示はブラウザ描画後の JS 効果のため要ブラウザ確認)
- **備考**: `buildAnalyzeMenu` に Bisulfite-Seq のときボタン非表示 (または「No analysis available」) を追加すれば旧と同等。

### SV-28 Download の `download` 属性ファイル名
- **ページ/機能**: /view > Download > BigWig / Peak-call
- **旧**: `hg38_HNF4A_Hep+G2_SRX018625.bw`、ピークは `…_SRX018625.05.bb` (**中身は `.bed` なのに拡張子 `.bb`**)。
- **新**: `hg38_HNF4A_Hep_G2_SRX018625.bw`、`…_SRX018625.05.bed` (英数字と `_-` 以外を `_` に置換)。URL 自体は新旧同一。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:112-121 / 新: frontend/pages/experiment.ts:29-31, 139-149
- **確認方法**: `ソース推定`
- **備考**: クロスオリジン (`chip-atlas.dbcls.jp`) の `download` 属性は主要ブラウザで無視されるため、実際の保存名はサーバ側 (`SRX018625.05.bed`) になる可能性が高い → 要ブラウザ確認。

### SV-29 Link Out の見出し「CellType:」→「Cell Type:」
- **ページ/機能**: /view > Link Out
- **旧**: 「Sequence Read Archive」(DDBJ Search / NCBI SRA / ENA)、「Antigen: HNF4A」(wikigenes / PDBj)、「**CellType:** Hep G2」(ATCC / MeSH / RIKEN BRC)、「Variation」(TogoVar、hg19/hg38 のみ)。
- **新**: 同じ構成・同じ URL で「**Cell Type:** Hep G2」。全項目 `rel="noopener noreferrer"`、値は `encodeURIComponent` (旧はブラウザ任せ、TogoVar だけ `Input+control` 形式)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:147-175; curl 本文 / 新: frontend/pages/experiment.ts:162-192
- **確認方法**: `curl+ソース確認済み`
- **備考**: Variation の `hg19` 判定は新にも残っているが hg19 データが無いので死に分岐。

### SV-30 Cell Type Information の `NA` 行の表示
- **ページ/機能**: /view > Sample Information Curated by ChIP-Atlas > Cell Type Information (例: SRX019491, SRX11233737)
- **旧**: `clSubClassInfo` が `NA` のとき「NA / NA」の 1 行 (ラベルも値も NA)。
- **新**: 「NA / (空)」(ラベル NA、値なし)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:212-214 (`split("=").first/last`) / 新: views/experiment.erb:57-61 (`split('=', 2)`); curl 本文差分
- **確認方法**: `curl+ソース確認済み`
- **備考**: どちらも無意味な行。`NA` はスキップするのが望ましい。副次的に、値に `=` を含む属性は新では全文が出る (旧は最後の断片のみ)。ただし該当データはローカル DB で見つからず。

### SV-31 Original Experimental Metadata: メッセージのアイコン削除
- **ページ/機能**: /view > Sample Attributes / Sequenced DNA Library / Sequencing Platform
- **旧**: 「No sample attributes were provided by the original submitter.」に ℹ アイコン、「No library information was found.」「No platform information was found.」に ⚠ アイコン。
- **新**: 同じ文言、アイコン無し (`text-muted`)。表示フィールド (library_name … key_sequence) と順序は同一。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:229-232, 246-249, 261-264 / 新: views/experiment.erb:76-78, 94-95, 107-108
- **確認方法**: `curl+ソース確認済み`

### SV-32 NCBI 取得失敗時の文言
- **ページ/機能**: /view > Sequenced DNA Library / Sequencing Platform
- **旧**: 各フィールドに「ERROR: cannot retrieve data from NCBI: too many requests」。
- **新**: 「ERROR: cannot retrieve data from NCBI」(理由句なし)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/lib/pj/sra.rb:64-86 / 新: lib/services/sra_service.rb:93-111
- **確認方法**: `ソース推定` (本番で実際にエラー表示になる瞬間は未観測)

### SV-33 NCBI メタデータのキャッシュ (初回のみ同期取得)
- **ページ/機能**: /view > 表示速度
- **旧**: 毎リクエストで NCBI eutils (esearch + efetch) を同期呼び出し。計測: `/view?id=SRX019491` 1.04 秒。API キー無し (3 req/s 制限) のため同時アクセスで「too many requests」エラーになりやすい。
- **新**: `sra_cache` テーブルに 30 日キャッシュ。未キャッシュ ID (`SRX9987853`) 初回 0.88 秒、2 回目 0.004 秒。SRX018625/SRX019491 は既にキャッシュ済みで 4 ms。
- **分類**: `改良`
- **影響度**: 高
- **根拠**: 旧: old-app/app.rb:266; sra.rb:7-11, 29-50 / 新: routes/pages.rb:37; lib/services/sra_service.rb:16-23; lib/models/sra_cache.rb:7-35; curl 計測
- **確認方法**: `curl+ソース確認済み`
- **備考**: 初回閲覧者の体感は旧と同じ (~1 秒、ローディング表示なし)。

### SV-34 NCBI 取得失敗の結果も 30 日間キャッシュされる
- **ページ/機能**: /view > Sequenced DNA Library / Sequencing Platform
- **旧**: キャッシュ無し。一時的な失敗は次のリクエストで回復する。
- **新**: `fetch_from_ncbi` は失敗時に `error_metadata` (Hash、真) を返し、`SraCache.set(...) if metadata` が **エラー結果もそのまま保存**。以後 30 日間、全閲覧者に「ERROR: cannot retrieve data from NCBI」が表示され続ける (NCBI の一時的な混雑・タイムアウトでも発生)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 新: lib/services/sra_service.rb:16-23 (`ChipAtlas::SraCache.set(@experiment_id, metadata) if metadata`), 37-48, 93-111; lib/models/sra_cache.rb:7 (`TTL_SECONDS = 30 日`)。ローカル `sra_cache` に ERROR 行は現時点で 0 件 (発生前)。
- **確認方法**: `ソース推定`
- **備考**: エラー時は `set` しない (または短い TTL) に変えるべき。`/api/remote_url_status` 側は「エラーはキャッシュしない」と明記して対処済み (routes/api.rb:243-253) なので、同じ方針を SRA にも。

### SV-35 NCBI 通信例外時の挙動 (500 か、エラー表示か)
- **ページ/機能**: /view 全体
- **旧**: `rescue OpenURI::HTTPError` のみ。タイムアウト・DNS 失敗などは例外がそのまま上がり **500 Internal Server Error** (ページ全体が出ない)。
- **新**: `SocketError / Timeout::Error / Errno::ECONNREFUSED / REXML::ParseException` を吸収してページは表示 (メタデータ欄のみ ERROR)。`OpenSSL::SSL::SSLError` や `Errno::ECONNRESET` は未吸収 (500 になり得る)。接続 10 秒/読取 15 秒のタイムアウト付き。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: sra.rb:29-50 / 新: lib/services/sra_service.rb:27-35, 46-47, 57-58
- **確認方法**: `ソース推定`

### SV-36 Read Processing Pipeline: 「Where can I get the processing logs?」リンクの削除
- **ページ/機能**: /view > Read Processing Pipeline パネル見出し
- **旧**: 見出し「Read Processing Pipeline」自体が wiki `#2-primary-processing` へのリンク、右側に「↗ Where can I get the processing logs?」→ wiki `#user-content-tables-summarizing-metadata-and-files`。
- **新**: 見出しはプレーン、右側に「↗ Pipeline docs」→ wiki `#2-primary-processing` (新規タブ)。ログ表へのリンクは無い。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:276-283; curl 本文 / 新: views/experiment.erb:127-130
- **確認方法**: `curl+ソース確認済み`
- **備考**: Search ページのリード文が同じ wiki 節 (`#tables-summarizing-metadata-and-files`) にリンクしているので導線は残っているが、/view からは辿れない。

### SV-37 Experiment Comparative Profile: ⓘ ヘルプ (説明文) の削除
- **ページ/機能**: /view > Experiment Comparative Profile > 各 h4 の ⓘ
- **旧**: 「Read and Peak Distribution ⓘ」→ alert「Distribution of sequence reads and called peaks across all experiments within the same experiment type (antigen class for ChIP-Seq). The orange horizontal line indicates the position of this experiment. For Bisulfite-Seq experiments, "peaks" should be interpreted as "hyper-methylated regions."」。「Correlation-Based Clustering ⓘ」→「Hierarchical clustering based on correlations among experiments sharing the same context (i.e., the combination of genome, antigen, and cell type). The arrowheads indicate this experiment, and their colors represent the median correlation of this experiment against all other experiments.」
- **新**: ⓘ 無し。図の読み方 (橙線・矢印の意味) を説明する文がページ上に無い。
- **分類**: `機能削除`
- **影響度**: 中
- **根拠**: 旧: experiment.haml:347-348, 363-364; experiment.js:22-25, 116-123 / 新: views/experiment.erb:177-189 (ヘルプ要素なし)
- **確認方法**: `curl+ソース確認済み`
- **備考**: info-popover 部品 (frontend/components/info-popover.ts) が既にあるので流用できる。

### SV-38 Comparative Profile: ローディング表示の削除と存在確認方式の変更
- **ページ/機能**: /view > Experiment Comparative Profile
- **旧**: パネルは非表示で開始し、各画像枠に「⟳ Checking for distribution data...」「⟳ Checking for clustering data...」を表示。ブラウザが `new Image()` で `chip-atlas.dbcls.jp` の PNG を直接読み込み、`onload` で表示 / `onerror` で枠を隠す。相関 PNG が読めたときだけ「Download Correlation Data」ボタンを表示。2 ゲノム間は `<hr>` 区切り。
- **新**: パネル・セクション・画像・リンクすべて `hidden` で開始し、ローディング表示なし。`/api/remote_url_status?url=…` (アプリサーバが HEAD、許可ホストのみ、200 は 1 時間キャッシュ) を dist/cor/tsv の 3 本並列で呼び、`'200'` のものだけ `src`/`href` を設定して表示。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:340-385; experiment.js:134-210 / 新: views/experiment.erb:158-204; frontend/pages/experiment.ts:200-265; routes/api.rb:231-254
- **確認方法**: `curl+ソース確認済み` (表示タイミングは要ブラウザ確認)
- **備考**: アプリサーバから `chip-atlas.dbcls.jp` に HEAD できない環境 (egress 制限) では、ブラウザからは見える画像でもパネルが出ない。SRX018625 の dist/cor PNG は 200 を確認済み。

### SV-39 Comparative Profile: 画像クリックの拡大モーダル削除
- **ページ/機能**: /view > Experiment Comparative Profile > 画像
- **旧**: 画像はカーソル pointer、クリックで Bootstrap モーダル (`modal-lg`、見出しは alt、Close ボタン) に拡大表示。
- **新**: クリック動作なし (`max-width:100%` の静止画像のみ)。
- **分類**: `機能削除`
- **影響度**: 低
- **根拠**: 旧: experiment.js:219-255 / 新: frontend/pages/experiment.ts (該当処理なし); style.css:511-516
- **確認方法**: `ソース推定`

### SV-40 相関 TSV のダウンロード UI
- **ページ/機能**: /view > Correlation-Based Clustering > TSV
- **旧**: ボタン「⬇ Download Correlation Data」(title「Download detailed correlation data in TSV format」)。クリックで `fetch` → Blob → `SRX018625_hg38__x__HNF4A__x__Hep_G2.correlation.tsv` という名前で保存、処理中は「⟳ Downloading...」。失敗時はリンク直開きにフォールバックし、alert「File opened in new tab. Use your browser's save function to download it.」
- **新**: プレーンリンク「⬇ Download correlation TSV」(TSV の HEAD が 200 のときだけ表示)。`download` 属性なし → ブラウザ既定動作 (サーバのファイル名 `hg38__x__HNF4A__x__Hep_G2.tsv` で保存、または `text/plain` ならインライン表示)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:375-383; experiment.js:257-333 / 新: views/experiment.erb:194; frontend/pages/experiment.ts:244-248
- **確認方法**: `ソース推定` (インライン表示になるかは要ブラウザ確認)

### SV-41 相関 TSV の URL 生成規則が旧と異なり、特殊文字を含む細胞種/抗原で 404 → リンクが出ない
- **ページ/機能**: /view > Correlation-Based Clustering > TSV リンク
- **旧**: `agSubClass`/`clSubClass` の **`[^a-zA-Z0-9_-]` をすべて `_`** に置換 (`CD4+ T cells` → `CD4__T_cells`、`H2A.Z` → `H2A_Z`、`Colon, Transverse` → `Colon__Transverse`)。データサーバの実ファイル名もこの規則: `hg38__x__H3K4me3__x__CD4__T_cells.tsv` → **200**、`hg38__x__ATAC-Seq__x__Colon__Transverse.tsv` → **200**。
- **新**: **空白だけ** `_` に置換 (`tr(' ', '_')`)。`hg38__x__H3K4me3__x__CD4+_T_cells.tsv` → **404**、`hg38__x__ATAC-Seq__x__Colon,_Transverse.tsv` → **404** (H3K27ac / H3K27me3 × CD4+ T cells も同様に旧 200 / 新 404)。HEAD が 200 でないためリンクは `hidden` のまま (画像は SRX 名なので表示される)。
- **分類**: `退行 (要修正)`
- **影響度**: 中
- **根拠**: 旧: experiment.haml:333-338 / 新: lib/services/location_service.rb:56-60; frontend/pages/experiment.ts:244-248; `chip-atlas.dbcls.jp` への HEAD 実測 (本文書作成時)。影響範囲: 本番 JSON 432,319 行中 **25,185 行 (5.8%)** の抗原/細胞種名が `[A-Za-z0-9_ -]` 以外を含む (細胞種 210 種: CD4+ T cells 5,037 / CD8+ T cells 3,879 / CD34+ 3,405 / NIH/3T3 744 / RAW 264.7 614 / Monocytes-CD14+ 610 …、抗原 55 種: H2A.Z 435 / H3.3 376 / H2A.XS139ph 266 / Su(var)205 61 …)。
- **確認方法**: `curl+ソース確認済み`
- **備考**: `correlation_tsv_url` を旧と同じ `gsub(/[^a-zA-Z0-9_-]/, '_')` にすれば解消。location_service_test.rb にこのケースの検証を追加すべき。

### SV-42 GSM → SRX リダイレクトと未知 GSM の扱い
- **ページ/機能**: /view?id=GSM… (navbar の ID → Go からの着地を含む)
- **旧**: `GSM469863` / `gsm469863` → 302 `/view?id=SRX018625` (`ExperimentList.json` から作った対応表)。未知の `GSM0000000` → **302 `/view?id=`** → 404 ページ (2 段階)。
- **新**: 同じく 302 `/view?id=SRX018625` (`experiments_fts.geo_id` 検索)。未知 GSM は **直接 404** ページ。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: old-app/app.rb:83, 260-265; curl 実測 / 新: routes/pages.rb:29-34; lib/models/experiment_search.rb:89-92; curl 実測
- **確認方法**: `curl+ソース確認済み`
- **備考**: 新の対応表は FTS 行 (= 非 Annotation の全実験) から引くので網羅性は旧と同等。

### SV-43 `/view` に id が無い場合
- **ページ/機能**: /view
- **旧**: **500** 「Internal Server Error」(`nil.upcase`)。
- **新**: **400** `{"error":"id parameter required"}` (JSON、HTML ページではない)。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: app.rb:261; `curl https://chip-atlas.org/view` → 500 / 新: routes/pages.rb:28; curl → 400
- **確認方法**: `curl+ソース確認済み`
- **備考**: ブラウザで開くと生 JSON が見えるので、人向けには 404 ページか `/search` へのリダイレクトの方が親切。

### SV-44 不正 ID の 404 ページ内容
- **ページ/機能**: /view?id=SRX0000000000 (存在しない ID)、`/view?id=`、空白混じり ID
- **旧**: 404 + `Location: https://chip-atlas.org/not_found` ヘッダ + 404 ページ本文「ChIP-Atlas: 404 / Sorry, could not find the requested resource. Try with different data or contact us.」+ Giphy のランダム gif (`http://api.giphy.com`、https ページからの混在コンテンツで恐らくブロック)。
- **新**: 同じステータス/ヘッダ/文言。gif の代わりに「Back to Home」「Report Issue」ボタン。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: app.rb:265, 447-449; old-app/views/not_found.haml:34-71; curl ヘッダ実測 / 新: routes/pages.rb:34, 152-164; views/not_found.erb; curl 実測
- **確認方法**: `curl+ソース確認済み` (404 ページ自体は他担当)

### SV-45 navbar「ID → Go」の初期値とエンコード
- **ページ/機能**: navbar > ID 入力 + Go
- **旧**: 初期値は `GSM469863` / `SRX018625` からページ表示ごとにランダム。`window.open("/view?id=" + 値)` (エンコード無し) を新規タブで開く。空でも `/view?id=` を開く (→404)。
- **新**: 初期値は常に `SRX018625`。`window.open('/view?id=' + encodeURIComponent(値))`、新規タブ。空でも同様に開く。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: old-app/views/_navigation.haml:58-65; old-app/public/js/pj/pj.js:21-27, 49-58 / 新: views/_navbar.erb:62-68
- **確認方法**: `curl+ソース確認済み` (window.open の挙動は要ブラウザ確認)
- **備考**: ランダム例が無くなり、GSM でも入力できることが伝わりにくくなった。

### SV-46 実験ページの `<html lang>`
- **ページ/機能**: /view
- **旧**: `<html lang="ja">` (英語ページなのに ja)。
- **新**: `lang="en"`。
- **分類**: `改良`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:2 / 新: views/layout.erb:2
- **確認方法**: `curl+ソース確認済み`

### SV-47 見出しレベル・レイアウト部品の変更
- **ページ/機能**: /view 全体
- **旧**: Bootstrap 3 `panel` (見出し `h3.panel-title`)、`dl.dl-horizontal` (ラベル右寄せ固定幅)、ゲノム見出し `h3 > small`、ボタンは `div.button.btn` (キーボード不可)。Bootstrap 3.2.0 CSS を maxcdn から読み込み。
- **新**: Bootstrap 5 `card` (見出し `h5`)、`dl.row` + `col-sm-5/7`、ゲノム見出し `h6.text-muted`、実 `<button>` + `aria-expanded`。同梱 CSS。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:14, 35, 121, 187-191, 292-296 / 新: views/experiment.erb:13-31, 41-47, 136-137
- **確認方法**: `ソース推定` (見た目は要ブラウザ確認)

### SV-48 メニュー項目の並び・文言 (差分なしの確認を含む)
- **ページ/機能**: /view > Visualize / Analyze / Download / Link Out の各項目
- **旧**: Visualize: BigWig / Peak-call (q < 1E-05, 1E-10, 1E-20)、Bisulfite-Seq は BigWig (Methylation rate) / BigWig (Coverage) / Hypo MR / Partial MR / Hyper MR。Analyze: Colocalization / Target Genes (TSS ± 1kb, 5kb, 10kb)。Download: Visualize と同じ 4 or 5 項目。
- **新**: 同一の文言・順序・URL (`https://chip-atlas.dbcls.jp/data/<genome>/eachData/…`, `…/colo/<SRX>.html`, `…/target/<SRX>.<kb>.html`)。ヘッダ「For hg38」も同じ。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: experiment.haml:48-77, 92-100, 115-132; curl 本文 / 新: frontend/pages/experiment.ts:70-160; curl 本文差分 (`SCR/sv/prod-view-*.txt` vs `new-view-*.txt`)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 実質差分なし (hg19 ブロックの消滅 = SV-24 を除く)。旧 experiment.js:65-113 の「Analyze リンク存在確認」は存在しない `ul#analysisLinkOut` を対象にしており無効なコードだったので、新旧とも Colo/Target Genes の有無に関わらずリンクが並ぶ。

### SV-49 サンプル情報・原メタデータ・QC 値の本文 (差分なしの確認)
- **ページ/機能**: /view > Sample Information Curated by ChIP-Atlas / Original Experimental Metadata / Read Processing Pipeline (hg38)
- **旧**: SRX018625: Antigen Class「TFs and others」/ Antigen「HNF4A」/ Cell Type Class「Liver」/ Cell Type「Hep G2」/ Primary Tissue「Liver」/ Tissue Diagnosis「Carcinoma Hepatocellular」; 属性 4 組; library_name「GSM469863: HNF4a_Fdomain_ChIPSeq」…; instrument_model「Illumina Genome Analyzer」; hg38: 9231367 / 94.3 / 3.1 / 6122 (qval < 1E-05)。見出し下タイトル「GSM469863: HNF4a Fdomain ChIPSeq」。
- **新**: SRX018625・SRX019491・SRX11233737 とも hg38 分は文言・数値が完全一致 (curl 本文 diff で差分は SV-24/SV-30/SV-31/SV-36/SV-37/SV-38 に挙げたもののみ)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: `SCR/sv/prod-view-SRX018625.txt` vs `new-view-SRX018625.txt`、同 SRX019491、同 bs (SRX11233737)
- **確認方法**: `curl+ソース確認済み`
- **備考**: 差分なし項目。Bisulfite-Seq の QC ラベル「Coverage rate (×)」「Number of hyper MRs」も一致。

### SV-50 Tutorial ドロップダウン (Search ページ)
- **ページ/機能**: Dataset Search > 右上 Tutorial
- **旧**: 「? Tutorial ▾」→「PDF」(`…/manual/Dataset_Search/Dataset_Search.pdf`、新規タブ)。
- **新**: 同じ (`_tutorial.erb`、`rel=noopener` 付き)。
- **分類**: `単なる変更`
- **影響度**: 低
- **根拠**: 旧: search.haml:43-51 / 新: views/search.erb:11-13; views/_tutorial.erb:9-16
- **確認方法**: `curl+ソース確認済み`
- **備考**: 差分なし項目。

---

## 差分なしを確認した事項 (依頼で確認を求められたもの)

- **検索結果 Title の `GSM####:` 接頭辞**: 旧 Detailed タブの Title は `ExperimentList_adv.json` の値で、本番 JSON 432,319 行中 `GSM…:` で始まる行は **0**。新の `experiments_fts.title` も同じ JSON 由来で接頭辞なし (`/api/search?q=SRX018625` → `"title":"HNF4a Fdomain ChIPSeq"`)。/view の見出し下タイトルは新旧とも `experimentList.tab` 由来で `GSM469863: HNF4a Fdomain ChIPSeq`。
- **SRX リンクの開き方**: 新旧とも新規タブ (SV-19)。
- **GEO ID リンク**: 新旧とも NCBI GEO へ新規タブ。
- **行クリック**: 新旧とも行自体はクリック不可 (リンクのみ)。
- **ディープリンク `?q=` `?genome=`**: 新旧とも未対応 (旧 DataTables は `stateSave` 無し、新 search.ts は `location.search` を読まない)。
- **大文字小文字**: 検索は新旧とも大小無視。/view の id は新旧とも `upcase` (`srx018625` → 200、`gsm469863` → 302)。
- **前後の空白付き id** (`%20SRX018625`): 新旧とも trim せず 404。
- **`id[]=…` (配列)**: 新旧とも `params[:id].upcase` で **500** (新はコンテナログ 14:11:42 / 14:15:47 UTC に `NoMethodError undefined method 'upcase' for an instance of Array` を確認。旧は app.rb:261 の同一コードからの推定)。
- **FastQC**: 旧 `lib/pj/fastqc.rb` は `lib/pj.rb` で require されるだけで app.rb/ビュー/JS から未使用。新旧とも UI に FastQC は出ない。
- **旧 `/data/search`**: サーバ側 FTS5 検索は旧にも存在するが Search ページからは使われていない (エージェント向け)。
- **Annotation tracks**: 新旧とも検索対象外。

## 要ブラウザ確認リスト

1. 旧 Search ページの実際の初期表示時間・メモリ (206 MB の JSON を DataTables が 2 表分処理) と、キー入力ごとのフィルタ応答。新の体感との比較 (SV-01, SV-06)。
2. 旧の Copy/TSV が無フィルタ (432,319 行) で完走するか、フィルタ後の全件が出力されるか (SV-15)。旧 TSV の Attributes セルの実際の書式 (`<br>` 除去後に語が連結されるか) (SV-16)。
3. 新の Attributes セル: 100 字省略 + `<details>` 展開の見た目 (マーカー非表示で「クリックできる」と分かるか)、Title/Attributes `max-width:320px` での折り返し、狭幅での横スクロール (SV-04, SV-18)。
4. 新の「Page 1 of 22697」表示と Previous/Next の無効化スタイル (SV-14)。
5. /view > Visualize: IGV 起動中/未起動それぞれで、新の「Contacting IGV…」→ 遷移 / 未到達メッセージが出ること。IGV 上でトラック名が旧と同じ「HNF4A (@ Hep G2) SRX018625 (1E-05)」になること (SV-25, SV-26)。
6. /view: 旧で Bisulfite-Seq (`SRX11233737`) の Analyze ボタンが実際に非表示になり、新では表示されること (SV-27)。
7. /view > Download: クロスオリジンの `download` 属性が無視され、保存名がサーバ名 (`SRX018625.05.bed`) になるか (SV-28)。
8. /view > Comparative Profile: 新で画像が (HEAD 経由で) 表示されるまでの空白時間、旧のローディング表示との違い、旧の拡大モーダル (SV-37〜SV-40)。TSV リンククリック時にインライン表示になるかダウンロードになるか (SV-40)。
9. /view の Bootstrap 3 → 5 でのレイアウト差 (dl-horizontal → dl.row、panel → card、ボタン列の折り返し) (SV-47)。
10. navbar ID → Go の `window.open` がポップアップブロックに掛からないか (新旧共通) (SV-45)。
11. 旧 404 ページの Giphy 画像が https 下で実際に表示されないこと (SV-44)。

## 未確認・不確実事項

- **ローカル環境での障害 (自分の作業が原因の可能性)**: 調査中に `sqlite3` CLI でホスト側から `database.sqlite.verify` (コンテナに bind mount、WAL モード) を直接読んだ。その最中の 14:14:54 UTC に新版が `Sequel::DatabaseError - SQLite3::IOException: disk I/O error` を返し (SRX11233737 の初回 /view が 500)、14:18:13 UTC に `sqlite3` 拡張内で `[BUG] Bus Error` (アドレスは `database.sqlite.verify-shm` の mmap 領域内) が発生して **コンテナ `chip-atlas-local` が Exited (133)** となった。SIGBUS 時点では私は DB に触っていなかったが、ホスト側プロセスが WAL の `-shm` を切り詰めるとコンテナ側がこの形で落ちるため、私 (14:14–14:15) や他エージェントのホスト側 `sqlite3` 利用が原因と推定。`docker start chip-atlas-local` で 14:21 UTC に再起動し (`/health` 200 を確認)、以降はホスト側 CLI での DB アクセスを止めた。**他エージェントにもホスト側 sqlite3 CLI で稼働中 DB を開かないよう周知が必要** (読み取り専用でも `-shm` を壊し得る)。この障害は新版アプリの欠陥ではなく、開発用 bind mount 構成の問題。
- コンテナログに他エージェントのプローブ由来と思われる 500 が複数 (`q[]=`/`limit[]=`/`id[]=` → `NoMethodError … for an instance of Array`、JSON ボディ形式違い → `undefined method '[]' for true` 等、14:15:47 / 14:16:00 UTC)。配列パラメータで 500 になる点は旧版も同じ実装だが、本番で意図的に発生させていないため旧側は推定。
- SV-07 の旧側件数は本番 JSON を DataTables 1.10.16 の smart 検索規則でローカル再現したもの (`SCR/sv/oldfilter.py`)。型判定 (`html` 型で HTML 除去) など DataTables 内部の細部は完全再現ではない。新旧でデータスナップショットが異なる (432,319 vs 453,932 行) ため件数は傾向比較。
- SV-21 の hg38 −171 / mm10 −44 / dm6 −5 が「スナップショット時期の差」か「tab/JSON 交差規則で落ちた行」かは未確認 (ロード時の `stats` を見れば分かる)。
- SV-34 (エラー結果のキャッシュ) は実際に NCBI 失敗を起こして確認したものではなく、ソースからの推定。
- SV-35: 旧版でタイムアウト時に 500 になる点は、本番で再現させていないためソース推定。
- SV-41 の影響数 (25,185 行) は「旧の置換規則で名前が変わる行」の数で、そのうち相関 TSV が実際にデータサーバに存在する組合せの数は未集計 (CD4+ T cells × H3K4me3/H3K27ac/H3K27me3、Colon, Transverse × ATAC-Seq の 4 例で 200/404 を確認)。
- 旧 Search の実ブラウザ挙動 (Simple タブ既定・番号付きページャ・Copy 完走可否) はソースと DataTables 既定からの推定で、実機未確認。
- 新版の `/view` 初回表示 (NCBI 同期取得) のうち、NCBI が遅い場合の最大待ち時間 (open 10 s + read 15 s × 2 リクエスト ≒ 最大 50 s) は未計測。
- 範囲外の気づき: 新版 navbar には旧版にある「Agents」リンクが無い (`views/_navbar.erb` に該当項目なし)。navbar 担当の確認事項として共有。
