# API サーフェス比較: 旧 chip-atlas.org vs 新 localhost:9292 (プログラム利用者の視点)

作成日: 2026-09-23 / 担当接頭辞: `API` / 検証: curl (本番は軽量 GET のみ、ローカルは任意) + ソース読解
証跡ファイル: `SCR/api/prod/<name>.{h,b}` (本番のヘッダ/本文)、`SCR/api/local/<name>.{h,b}` (ローカル)、`SCR/api/container-crash-stderr.log` (ローカル新版のクラッシュログ)

## 担当範囲の要約

1. 旧アプリの HTTP ルート 36 本 (app.rb、not_found 除く) と静的データ 12 種、新アプリのルート 47 本 (routes/*.rb、not_found 除く) と静的ファイルを全数列挙し、対応表を作った (第 1 章)。
2. **旧 API パスは新版で例外なく 404** (`/data/*`, `/qvalue_range`, `/browse`, `/download`, `/colo` POST, `/target_genes` POST, `/wabi_*`, `/*_log`, `/diff_analysis_estimated_time`, `/api/remoteUrlStatus`, `/.well-known/mcp.json`)。リダイレクトや互換シムは一切無い (ローカル curl で 27 パス確認)。旧 MCP サーバ (10 ツール) はこれらのパスに依存するため、カットオーバー後は全ツールが失敗する。
3. 同一データに対する応答形状は、キー名の camelCase→snake_case を除けば概ね同型 (分類 API の `{id,label,count}`、順序、`count:null` の扱いは一致)。型が変わるのは `/api/genomes` (配列→オブジェクト)、`colo_index` (`antigen/cellline`→`track/cell_type`)、`genome_index` (`antigen/celltype`→`track/cell_type`)、検索結果の `genome` (連結文字列→単一値)。
4. 旧版の実バグを新版が直している点: `/data/search` の `genome=` フィルタが本番では常に 0 件 (連結文字列 "hg19, hg38" と等値比較)、`colo_analysis.json` に `"-"` がセルタイプとして混入 (hg38 で 114 antigen)、`/colo_result?base=` `/target_genes_result?base=` が未定義ヘルパ呼び出しで本番 500。
5. エラー契約が改善: 新版は 400/404/502/503 を JSON `{"error":...}` で返す (旧は 200 + `null`/`[]`/空、または 500 HTML)。`/api/*` の未知パスも JSON 404。
6. 新版のドキュメント (`openapi.yaml` v2.0.0, `llms.txt`, `/agents`) は `/api/` に更新済みだが、**実装と食い違う箇所が 13 点以上** ある (genomes の型、experiment の型、/status の形、jobs 系の応答形状、TAIR10 vs TAIR12、CUT&Tag/CUT&RUN の記載、K-562 を cell_type とする例、ログの Content-Type など)。機械可読 spec としては現状使えない。
7. diff_analysis のジョブ投入は新版では常に 503 (`ComputeRouter::JOB_TYPE_BACKENDS['diff_analysis'] = []`)。/status も `diff_analysis: unavailable`。
8. 挙動面: CORS ヘッダは旧新とも無し、Host 認可は旧新とも `.chip-atlas.org` のみ許可、JSON は両方コンパクト。新版は `Cache-Control` を API に付与 (旧は無し; 本番は nginx の proxy cache `x-cache` が別途ある)。新版は POST に `Content-Type: application/json` を要求する。
9. 監査中にローカル新版が Ruby VM の `[BUG] Bus Error` (sqlite3 `step`、`/api/search` 処理中、フォルト先は bind mount 上の `database.sqlite.verify-shm` の mmap) で落ちた。`docker start chip-atlas-local` で復旧させた (環境操作をした旨、明記)。本番環境 (ローカルディスク) での再現性は不明。

---

## 1. ルート対応表 (旧 → 新)

凡例: 分類は API 利用者視点。`確認` 列: C = curl+ソース確認済み, S = ソース推定。証跡は `SCR/api/{prod,local}/` 配下のファイル名 (拡張子 `.h` ヘッダ / `.b` 本文)。

### 1-A. データ・分類 API

| # | 旧 (method path) | 旧パラメータ | 新 (method path) | 新パラメータ | 応答形状・挙動の差 | エラー時 (旧 → 新) | 新 Cache-Control | 分類 | 確認 |
|---|---|---|---|---|---|---|---|---|---|
| A1 | GET `/data/list_of_genome.json` (app.rb:113-118) | なし | GET `/api/genomes` (routes/api.rb:48) | なし | 旧: `["hg38","hg19",...]` 配列 10 件 / 新: `{"hg38":"H. sapiens (hg38)",...}` オブジェクト 7 件 (順序は config/genomes.yml) | – | `public, max-age=86400` | 単なる変更 (型変更) + データ差分 | C (prod/list_of_genome, local/genomes) |
| A2 | GET `/data/list_of_experiment_types.json` (app.rb:119) | なし | GET `/api/track_classes` (api.rb:58-64) | なし | 同一 `[{id,label}]` 8 件 (Annotation tracks 含む)。count キー無し | – | `public, max-age=86400` | 単なる変更 (パスのみ) | C |
| A3 | GET `/data/experiment_types` (app.rb:147-154) | `genome`, `clClass` | GET `/api/track_classes` (api.rb:58-61) | `genome`, `cell_type_class` (省略時 `All cell types`) | 同一 `[{id,label,count}]`。旧は clClass 必須 (無いと count 全 null)、新は既定値あり | 旧: パラメータ無し → 200 count 全 null / 新: genome 無し → 静的一覧 | なし (genome 指定時) | 改良 | C (prod/experiment_types*, local/track_classes_*) |
| A4 | GET `/data/sample_types` (app.rb:156-163) | `genome`, `agClass` | GET `/api/cell_type_classes` (api.rb:67-70) | `genome`, `track_class` | 同一形状・同一順序 (hg38/Histone で 1106 バイト完全一致) | 旧: 欠落 → 200 `[{All cell types,count:0}]` / 新: 400 `{"error":"genome and track_class required"}` | なし | 改良 | C |
| A5 | GET `/data/chip_antigen` (app.rb:165-173) | `genome`, `agClass`, `clClass` (`undefined` 番兵) | GET `/api/track_subclasses` (api.rb:72-75) | `genome`, `track_class`, `cell_type_class` (`undefined` 番兵維持) | 同一形状・順序 (hg38/Histone/Blood 64 件同一)。**両方とも clClass/cell_type_class を省略すると `[{"-","All",null}]` のみ** (undefined か All cell types を明示する必要) | 旧: 欠落 → 200 / 新: genome/track_class 欠落 → 400 | なし | 単なる変更 | C (prod/chip_antigen*, local/track_subclasses*) |
| A6 | GET `/data/cell_type` (app.rb:175-183) | 同上 | GET `/api/cell_type_subclasses` (api.rb:77-80) | 同上 | 同一形状・順序 (15759 バイト一致) | 同上 | なし | 単なる変更 | C |
| A7 | GET `/data/exp_metadata.json` (app.rb:123-124) | `expid` | GET `/api/experiment` (api.rb:89-92) | `experiment_id` | 配列 (ゲノムごと 1 レコード)。キー camel→snake。旧の並びは genome の数字降順 (hg38,hg19)、新は genomes.yml 順。GSM は両方 `[]` (未解決) | 旧: 欠落/不明 ID → 200 `[]` / 新: 欠落 → 400、不明 ID → 200 `[]` | なし | 単なる変更 + データ差分 | C (prod/exp_metadata*, local/experiment*) |
| A8 | GET `/data/search` (app.rb:185-192) | `q`, `genome`, `limit` (1-100) | GET `/api/search` (api.rb:94-101) | `q`, `genome`, `limit` (1-100), **`offset`** | `{total,returned,experiments[]}` 同型、キー snake。旧 `genome` は "hg19, hg38" の連結文字列で **genome= フィルタは本番で常に 0 件**。新は単一値で正しく絞れる。空 `q`: 旧 0 件 / 新は全件一覧 (experiment_id 順)。`attributes` は両方 `__TAB__` 区切り | 両方 200 | なし | 改良 (旧バグ修正) | C (prod/search*, local/search*) |
| A9 | GET `/qvalue_range` (app.rb:227) / GET `/data/qval_range.json` (app.rb:121) | なし | GET `/api/qval_range` (api.rb:103) | なし | 同一 `["05","10","20","50"]` | – | `public, max-age=3600` | 単なる変更 | C |
| A10 | GET `/data/number_of_lines.json` (app.rb:130) | なし | GET `/api/bed_sizes` (api.rb:108) | なし | 同一形状 `{"genome,agClass,clClass,qval": int}` (キーは旧語彙 "All antigens" のまま)。4924 → 3127 件 (ゲノム集合の差) | – | `public, max-age=3600` | データ差分 | C |
| A11 | GET `/data/index_all_genome.json` (app.rb:115) | なし | GET `/api/genome_index` (api.rb:84) | なし | `{genome:{antigen:{class:{sub:n}},celltype:{...}}}` → `{genome:{track:{...},cell_type:{...}}}`。ゲノム 10 → 7 | – | `public, max-age=3600` (+ サーバ内 1h キャッシュ) | 単なる変更 | C |
| A12 | GET `/data/colo_analysis.json` (app.rb:125-127) | `genome` | GET `/api/colo_index` (api.rb:115-119) | `genome` | `{genome:{antigen:{ag:[cl]},cellline:{cl:[ag]}}}` → `{genome:{track:{...},cell_type:{...}}}`。旧は cell_list "-" をそのまま出す (hg38: antigen 114 件が `["-"]`、cellline に `"-"` キー)。新は除去 (1767→1653) | 旧: genome 無し → 200 `{"":{}}` / 新: 400 | `public, max-age=3600` | 改良 | C (prod/colo_analysis*, local/colo_index*) |
| A13 | GET `/data/target_genes_analysis.json` (app.rb:128) | なし | GET `/api/target_genes_index` (api.rb:121) | なし | 同一形状 `{genome:[antigen]}`。hg38/mm10 の名前集合は完全一致。新は TAIR12 (77 件) 追加、hg19/mm9/dm3/ce10 削除 | – | `public, max-age=3600` | データ差分 | C |
| A14 | GET `/data/index_subclass.json` (app.rb:132-137) | `genome`,`agClass`,`clClass`,`type=ag\|cl` | **なし** | – | `{subclass: count}` 形式。代替は A5/A6 または A11 | 新: 404 HTML | – | 機能削除 | C (prod/index_subclass, local/old_* 404) |
| A15 | GET `/data/ExperimentList.json` / `/data/ExperimentList_adv.json` (app.rb:138-141; 本番では nginx が静的配信、ETag 付き 44MB/161MB) | なし | **なし** (`/api/search` で代替、llms.txt:36 に明記) | – | 一括ダンプ廃止。ルート直下の静的 `/ExperimentList.json` は作業ツリーでは 200 だが `.dockerignore`:11-12 で本番イメージから除外 | 新: 404 HTML | – | 機能削除 (意図的) | C + S (イメージ除外は推定) |
| A16 | GET `/data/<未知>.json` | – | GET `/api/<未知>` | – | 旧: 200 `null` / 新: 404 `{"error":"Not found"}` | – | – | 改良 | C (prod/unknown_json, local/api_unknown) |
| A17 | – | – | GET `/api/stats` (api.rb:53) | なし | `{total_experiments, total_experiments_formatted, by_genome, by_track_class}` | – | `public, max-age=3600` | 新機能 | C |
| A18 | – | – | GET `/api/target_genes_distances` (api.rb:126) | なし | `[{id:"1",label:"1 kb"},...]` | – | `public, max-age=86400` | 新機能 | C |

### 1-B. URL 生成・解析結果

| # | 旧 | 旧パラメータ | 新 | 新パラメータ | 差 | エラー時 | Cache | 分類 | 確認 |
|---|---|---|---|---|---|---|---|---|---|
| B1 | POST `/browse` (app.rb:243-249) | JSON body `{condition:{genome,agClass,agSubClass,clClass,clSubClass,qval},igv?}` (Content-Type 不問) | GET/POST `/api/igv_url` (api.rb:133-142) | GET: query `genome,track_class,track_subclass,cell_type_class,cell_type_subclass,qval` / POST: JSON `{condition:{...},igv?}` (application/json 必須) | 応答同型 `{"url":"http://localhost:60151/load?genome=..&file=..."}`。GET では `igv` を指定できない | 旧: 該当なし → `{"url":"...&file="}` 相当 (`archived_bed_url` nil) / 新: 必須欠落 → 400 JSON、該当なし → `file=` 空。Annotation tracks で不明 subclass → **旧新とも 500** (get_trackname の例外未捕捉) | なし | 単なる変更 | C (local/igv_url*, post_igv_url) + S (旧 POST は本番未実行) |
| B2 | POST `/download` (app.rb:251-258) | 同上 | GET/POST `/api/download_url` (api.rb:144-153) | 同上 | 応答同型 `{"url": "https://chip-atlas.dbcls.jp/data/hg38/assembled/His.Bld.05.H3K4me3.AllCell.bed"}`。旧は拡張子 `.bed` 固定、新は `.bed`/`.bed.gz` をアーカイブに HEAD で探索 (bed_extension_resolver.rb:27,81-89) | 該当なし: 両方 200 `{"url":null}`。新: JSON 無し/不正 → 400、`condition` 無し → 400。**旧キー名 (agClass 等) で送ると 200 `{"url":null}` で無言失敗** | なし | 改良 (gz 移行対応) | C (local/download_url*, post_download_url*) |
| B3 | POST `/colo?type=submit\|tsv\|gml` (app.rb:280-286, lib/pj/location.rb:70-82) | JSON `{condition:{genome,antigen,cellline}}` | GET `/api/colo` (api.rb:158-171) + GET `/api/colo/download?format=tsv\|gml` (api.rb:174-187) | `genome`, `track`, `cell_type` (+`format`) | 旧: dbcls 上の HTML/TSV/GML の **URL を返す**。新: TSV を取得・解析した JSON `{columns,rows,total,genome,track,cell_type}` (Average 降順、全行、キャッシュ無し) と、ファイルのプロキシ配信 (`Content-Disposition: attachment; filename="STAT3.Blood.tsv"`)。dbcls の URL 自体は返さない。gml は cell type 単位のファイル (`Blood.gml`, 33MB) を `STAT3.Blood.gml` の名前で丸ごとメモリに載せて配信 | 旧: type 不正 → 200 `{"url":null}` / 新: 欠落 → 400、無し → 404 JSON、解析不能 → 502 | なし | 単なる変更 + 新機能 (JSON 化) | C (local/colo*, colo_dl*) |
| B4 | POST `/target_genes?type=submit\|tsv` (app.rb:308-314, location.rb:88-99) | JSON `{condition:{genome,antigen,distance}}` | GET `/api/target_genes` (api.rb:192-212) + GET `/api/target_genes/download?format=tsv` (api.rb:215-227) | `genome`, `track`, `distance`, `sort`, `order`, `offset`, `limit` (既定 50, 上限 500), `q` | 旧: URL を返す。新: `{columns,rows,total,offset,limit}` (サーバ側ソート・ページング・遺伝子名部分一致、5 分/150MB キャッシュ; target_genes_tsv.rb:61-62,136-158) | 旧: 200 `{"url":"...html"}` (存在確認なし) / 新: 欠落 → 400、`sort` 不正 → 400、無し → 404、解析不能 → 502 | なし | 新機能 | C (local/target_genes*) |
| B5 | GET `/colo_result?base=URL` / GET `/target_genes_result?base=URL` (app.rb:288-296, 316-324) | `base` | GET `/colo_result?genome&track&cell_type` / GET `/target_genes_result?genome&track&distance` (routes/pages.rb:62-82; frontend/pages/colo-result.ts:53-58) | – | 旧は未定義ヘルパ `remotefile_available?` (定義は lib/pj/fastqc.rb:100 のインスタンスメソッドのみ) を呼ぶため **本番で 500** (旧 UI は使わず dbcls へ直接遷移 colo.js:191)。新はアプリ内描画ページ | 旧: 500 / 新: パラメータ欠落は JS 側でエラー表示 | – | 改良 | C (prod/colo_result 500) |

### 1-C. ジョブ (WABI / WES)

| # | 旧 | 旧パラメータ | 新 | 新パラメータ | 差 | エラー時 | Cache | 分類 | 確認 |
|---|---|---|---|---|---|---|---|---|---|
| C1 | GET `/wabi_endpoint_status` (app.rb:455-457) | なし | GET `/status` (routes/health.rb:27-40) + GET `/jobs/available?type=` (routes/jobs.rb:45-48) | `type` (既定 enrichment_analysis) | 旧: 本文 `chipatlas` または空 (text/html)。新: `{services:{data_server,wabi,wes:"ok"\|"down"\|"not_checked"},features:{peak_browser,colo,target_genes,search,enrichment_analysis,diff_analysis}}` (60 秒サーバ内キャッシュ) と `{backend:"wabi"\|"wes"\|null, available}` | – | `/status`: `public, max-age=30` | 単なる変更 | C (prod/wabi_endpoint_status, local/status, jobs_available*) |
| C2 | POST `/wabi_chipatlas` (app.rb:477-501) | form または JSON、WABI のフィールド名そのまま (`address`,`format`,`result`,`sbatchOptions` を含めクライアントが全て送る) | POST `/jobs/submit` (jobs.rb:51-75) | JSON `{type:"enrichment_analysis"\|"diff_analysis", params:{WABI 名 (camelCase)}}` のみ | 応答 旧: `{"requestId": id}` (Content-Type は text/html) / 新: `{backend, job_id}`。運用パラメータはサーバが付与 (wabi_service.rb:19-24) | 旧: WABI 停止 → 503 空本文、解析失敗 → 404 HTML へリダイレクト / 新: バックエンド無し → 503 `{"error":"No compute backend available","retry":false}`、拒否 → 502、JSON 無し → 400 | なし | 単なる変更 | C (local/post_jobs_submit_*) + S (成功応答は routes/jobs.rb:59, compute_router.rb:59 から; 実投入はしていない) |
| C3 | (同上、`antigenClass=dmr\|diffbind`) | – | POST `/jobs/submit` `type=diff_analysis` | – | **新版は diff_analysis を常に 503** (compute_router.rb:21-24 `'diff_analysis' => []`)。`/jobs/available?type=diff_analysis` → `{backend:null,available:false}`、`/status` → `diff_analysis:"unavailable"` | 503 | – | 機能削除 (意図的、コメントは WABI 側都合) | C (local/post_jobs_submit_diff, jobs_available_diff) |
| C4 | GET `/wabi_chipatlas?id=` (app.rb:460-474) | `id` | GET `/jobs/:id/status?backend=wabi\|wes` (jobs.rb:78-91) | `backend` 必須、`id` は `[\w-]+` のみ | 旧: 本文 `finished`/`running`/`server unavailable` (HTML 結果の 200 判定)。新: `{backend, job_id, status: WABI の status 語 ("finished","running",...) or "unknown", retry}` (`?info=status` を使用 wabi_service.rb:106-118) | 旧: 200 テキスト / 新: backend 不正 → 400、id 不正 → 400、backend 停止 → 503 JSON | なし | 改良 | C (local/jobs_status_*) + S (旧応答文字列は本番未実行) |
| C5 | – | – | GET `/jobs/:id/result?backend=&type=` (jobs.rb:94-104) | `backend`, `type` (既定 enrichment_analysis) | `{backend, job_id, urls:{html,tsv}}` または diff の `{urls:{zip}}`。旧はクライアントが URL を組み立て | type 不正 → 400 | なし | 新機能 | C |
| C6 | GET `/enrichment_analysis_log?id=` / GET `/diff_analysis_log?id=` (app.rb:374-390) | `id` | GET `/jobs/:id/log?backend=` (jobs.rb:107-122) | `backend` | 200 時 旧 text/html / 新 text/plain。**404 時は旧新とも HTML の 404 ページ** (旧: "Log file not available yet" が not_found ハンドラに上書き app.rb:447; 新: "Log not available yet" も pages.rb:152-164 の判定が Content-Type 依存のため上書き) | 404 HTML | なし | 単なる変更 (要修正候補) | C (prod/diff_log, local/jobs_log) |
| C7 | POST `/diff_analysis_estimated_time` (app.rb:392-417) | JSON `{analysis:"dmr"\|"diffbind", ids:[...]}` | POST `/jobs/estimated_time` (jobs.rb:125-134) | 同じ (application/json 必須) | 同一 `{"minutes": n\|null}` | 新: JSON 無し → 400 | なし | 単なる変更 | C (local/post_estimated_time*) |

### 1-D. その他ルート (プログラム利用に関係するもの)

| # | 旧 | 新 | 差 | 分類 | 確認 |
|---|---|---|---|---|---|
| D1 | GET `/api/remoteUrlStatus?url=` (app.rb:503-505): 任意 URL を GET (本文丸ごと取得) し、**上流のステータスコードを HTTP ステータスとして返す (本文空)** | GET `/api/remote_url_status?url=` (api.rb:231-254): 許可ホスト (chip-atlas.dbcls.jp, dtn1.ddbj.nig.ac.jp とそのサブドメイン) のみ、HEAD、**本文に "200" 等の文字列、HTTP は 200**、失敗時本文 "500"; 不許可/欠落 → 400 "Invalid or disallowed URL" | 契約変更 + SSRF 封じ。上流応答時のみ `public, max-age=3600` | 改良 (契約は非互換) | C (prod/remoteUrlStatus: 200 空, remoteUrlStatus_noparam: 500 / local/remote_url_status*) |
| D2 | GET `/health` (app.rb:194-220): `{status, checks:{database, config}}` | GET `/health` (health.rb:8-24): `{status, checks:{database, experiments}}` | キー `config`→`experiments`。503 条件は DB 失敗のみ | 単なる変更 | C |
| D3 | GET `/:source.css` (app.rb:109-111): `/style.css` を SASS から動的生成 (4172 B) | なし (`/css/style.css` 静的 18461 B) | 旧パス 404 | 機能削除 (意図的) | C |
| D4 | GET `/view?id=` (app.rb:260-268): GSM→SRX リダイレクト、id 無しは 500 | GET `/view?id=` (pages.rb:27-54): 同じリダイレクト (302)、id 無しは 400 JSON | – | 改良 | C (prod/view_noid 500, local/view_noid 400, view_gsm 302) |
| D5 | 結果ページ `/enrichment_analysis_result?id=&api=wabi&title=&calcm=` (enrichment_analysis.js:730-733, 777-779), `/diff_analysis_result?id=&title=...` | `?id=&backend=wabi&title=&calcm=` (result-page-params.ts:4-9, 33-36; enrichment-analysis.ts:783-786) | `api=` → `backend=`。`backend` 無しはエラー表示 | 単なる変更 | C (ソース) |
| D6 | POST `/enrichment_analysis` (form: taxonomy, genes, genesetA/B; app.rb:337-353) | POST `/enrichment_analysis` (pages.rb:90-99) | 同じ (HTML を返すページ) | 単なる変更 (なし) | S |
| D7 | 未知パス → HTML 404 (6513 B) | 未知 `/api/*` → JSON `{"error":"Not found"}`、それ以外 → HTML 404 (7846 B) | – | 改良 | C |
| D8 | OPTIONS (CORS preflight) → 404 HTML | → 404 JSON (`/api/*`) | Access-Control-* ヘッダは旧新とも無し | 単なる変更 (なし) | C (prod/cors*, local/cors*) |

### 1-E. 静的ファイル・ドキュメント

| # | パス | 旧 (本番) | 新 (ローカル) | 分類 | 確認 |
|---|---|---|---|---|---|
| E1 | `/openapi.yaml` | v1.0.0、11 paths、`application/octet-stream` (nginx)、old-app/public と同一 | v2.0.0、26 paths、`text/yaml`、リポジトリと同一 | 単なる変更 (内容は第 2 章 API-46) | C |
| E2 | `/llms.txt` | 5345 B、`/data/*` 記載 | 8957 B、`/api/*` 記載 | 単なる変更 (誤記は API-47) | C |
| E3 | `/.well-known/mcp.json` | 883 B、10 ツール名・install 情報 | **404** (`public/.well-known/` は空ディレクトリ) | 機能削除 | C |
| E4 | `/agents` | MCP 節 + `/data/*` 表 (17994 B) | HTTP API のみ (19423 B) | 単なる変更 (誤記は API-48) | C |
| E5 | `/robots.txt` | 496 B | 同一バイト列 (`Disallow: /data /browse /download /wabi_chipatlas` は死にパス; `/jobs` `/status` は未記載) | 単なる変更 (なし) | C |
| E6 | `/ExperimentList.json`, `/ExperimentList_adv.json` | 200 (nginx 静的、44MB / 161MB、2025-10-24 版) | 作業ツリーでは 200 (44MB / 170MB、2026-09-13 版)。`.dockerignore` で除外 → 本番イメージでは 404 と推定 | 機能削除 (推定) | C + S |
| E7 | `/analysisList.tab` | 200 octet-stream (2018-04-16 版 32228 B) | 200 octet-stream (同サイズ) | 単なる変更 (なし) | C |
| E8 | `/tables/lineNum.tsv` | 200 octet-stream | 200 `text/tab-separated-values` | 単なる変更 | C |
| E9 | `/tables/exp2run.json` | 200 (34MB) | **404** (ファイル無し) | 機能削除 | C |
| E10 | `/diff-analysis.examples.json`, `/examples/<genome>/*.txt` | 200 | 200 (examples には hg19/mm9/dm3/ce10 も残置) | 単なる変更 (なし) | C (ls) |

---

## 2. 差分項目

### API-01 旧 API パス全廃止・互換シム無し
- **ページ/機能**: 全 API (`/data/*`, `/qvalue_range`, `/browse`, `/download`, `/colo` POST, `/target_genes` POST, `/wabi_endpoint_status`, `/wabi_chipatlas`, `/diff_analysis_log`, `/enrichment_analysis_log`, `/diff_analysis_estimated_time`, `/api/remoteUrlStatus`, `/.well-known/mcp.json`, `/data/ExperimentList*.json`, `/style.css`)
- **旧 (chip-atlas.org)**: 上記 27 パスが 200 で応答 (第 1 章)
- **新 (localhost:9292)**: 全て 404。`/api/remoteUrlStatus` は `{"error":"Not found"}` JSON、その他は HTML 404 ページ。`routes/*.rb`、`app.rb` に `/data/` を扱うルートは無く (grep 0 件)、リダイレクトも無い
- **分類**: 機能削除 (意図的; BRIEF の「API パス `/data/*` → `/api/*`」)
- **影響度**: 高
- **根拠**: 旧: old-app/app.rb:113-192, 227, 243-258, 280-286, 308-314, 374-417, 455-505 / 新: `SCR/api/local/old_*.h` (27 ファイル全て 404)
- **確認方法**: curl+ソース確認済み
- **備考**: 既存のスクリプト・Jupyter ノート・旧 MCP サーバは全て壊れる。最低限、旧 GET パスに対する 301/308 リダイレクト (例: `/data/list_of_genome.json` → `/api/genomes` は型が違うので不可、`/data/experiment_types?genome=X&clClass=Y` → `/api/track_classes?genome=X&cell_type_class=Y` 等) か、`410 Gone` + JSON で新パスを案内する薄い互換層を検討する価値がある。旧 openapi/llms.txt/agents ページが検索エンジンや LLM の学習データに残るため、当面は問い合わせが来る。

### API-02 MCP サーバの廃止 (旧 MCP はカットオーバー後に全ツールが失敗)
- **ページ/機能**: `.well-known/mcp.json`、`mcp/` (TypeScript stdio サーバ、10 ツール)
- **旧**: `https://chip-atlas.org/.well-known/mcp.json` が 10 ツール名と `node mcp/dist/index.js` の起動情報を配信。ツール実装は `/data/list_of_genome.json`, `/data/list_of_experiment_types.json`, `/data/experiment_types`, `/data/sample_types`, `/data/chip_antigen`, `/data/cell_type`, `/data/ExperimentList.json` (検索はクライアント側で 44MB を全件フィルタ), `/data/exp_metadata.json`, `/data/colo_analysis.json`, `/data/target_genes_analysis.json`, POST `/download` を叩く
- **新**: `mcp/` ディレクトリ無し、`public/.well-known/` は空 (404)、ドキュメントから MCP の記述を削除。代替の MCP 提供は無し
- **分類**: 機能削除 (意図的)
- **影響度**: 高
- **根拠**: 旧: old-app/public/.well-known/mcp.json, old-app/mcp/src/client.ts:46-150, old-app/mcp/src/index.ts / 新: `ls public/.well-known` (空), `SCR/api/local/old_mcp_json.h` (404)
- **確認方法**: curl+ソース確認済み
- **備考**: エージェント利用者が失うもの: (1) Claude Desktop 等から stdio で接続できる既製ツール、(2) `chipatlas_get_bed_url` のような引数バリデーション付きラッパ。代わりに新版は GET だけで完結する `/api/download_url`, `/api/colo`, `/api/target_genes` を持つので、HTTP 直叩きのエージェントには有利。ただし旧 MCP を `CHIP_ATLAS_BASE_URL=https://chip-atlas.org` で使い続けている利用者は、切替日に 10/10 ツールが `HTTP 404` で例外になる (client.ts:20-22)。

### API-03 フィールド名・クエリ名 camelCase → snake_case
- **ページ/機能**: 全 JSON API
- **旧**: 応答キー `expid, agClass, agSubClass, clClass, clSubClass, readInfo, clSubClassInfo`; クエリ `expid, agClass, clClass`; body `condition.{agClass,agSubClass,clClass,clSubClass,antigen,cellline}`
- **新**: `experiment_id, track_class, track_subclass, cell_type_class, cell_type_subclass, read_info, cell_type_subclass_info`; クエリ `experiment_id, track_class, cell_type_class, track, cell_type`; body `condition.{track_class,...}`。`sra_id, geo_id, genome, title, attributes, id, label, count, total, returned, experiments, url, minutes` は不変
- **分類**: 単なる変更
- **影響度**: 高 (非互換)
- **根拠**: 旧: old-app/lib/pj/experiment.rb:34-50, experiment_search.rb:66-79 / 新: lib/models/experiment.rb:185-191, experiment_search.rb:5-6, routes/api.rb:23-37; `SCR/api/prod/exp_metadata.b` vs `SCR/api/local/experiment.b`
- **確認方法**: curl+ソース確認済み
- **備考**: `/api/bed_sizes` のキー文字列 (`"hg38,Histone,Blood,05"`) だけは旧語彙 ("All antigens", "All cell types") のまま。

### API-04 `/data/list_of_genome.json` (配列) → `/api/genomes` (オブジェクト)
- **ページ/機能**: ゲノム一覧
- **旧**: `["hg38","hg19","mm10","mm9","rn6","dm6","dm3","ce11","ce10","sacCer3"]`
- **新**: `{"hg38":"H. sapiens (hg38)","mm10":"M. musculus (mm10)","rn6":...,"dm6":...,"ce11":...,"sacCer3":...,"TAIR12":"A. thaliana (TAIR12)"}` (`Cache-Control: public, max-age=86400`)
- **分類**: 単なる変更 (型変更) + データ差分
- **影響度**: 中
- **根拠**: 旧: app.rb:117-118 (`settings.list_of_genome.keys`) / 新: routes/api.rb:48-51, lib/models/experiment.rb:122-124, config/genomes.yml; `SCR/api/prod/list_of_genome.b`, `SCR/api/local/genomes.b`
- **確認方法**: curl+ソース確認済み
- **備考**: `Object.keys()` すれば旧と同じ配列になるが、`for (g of genomes)` のようなコードは壊れる。新 openapi.yaml:403-418 は「配列」と書いており実装と不一致 (API-46)。

### API-05 `/data/list_of_experiment_types.json` → `/api/track_classes` (無引数)
- **ページ/機能**: 実験タイプ静的一覧
- **旧/新**: 383 バイト完全一致 (`[{id,label}]` 8 件、"Annotation tracks" を含む、count キー無し)
- **分類**: 単なる変更 (パスのみ)
- **影響度**: 低
- **根拠**: `SCR/api/prod/list_of_experiment_types.b` = `SCR/api/local/track_classes.b`; lib/models/experiment.rb:21-30
- **確認方法**: curl+ソース確認済み
- **備考**: llms.txt / openapi / agents が列挙する "CUT&Tag", "CUT&RUN" は一覧にもデータ (`/api/stats` の by_track_class) にも存在しない (API-47)。

### API-06 `/data/experiment_types` → `/api/track_classes?genome=`
- **ページ/機能**: 実験タイプ別件数
- **旧**: `genome` と `clClass` の両方が必要。`clClass` を省略すると `where(clClass: nil)` で全 count が null (パラメータ無しの本番応答は全 null)
- **新**: `cell_type_class` 省略時は `'All cell types'` を既定。hg38 の count は本番と同値 (Histone 36073, Blood 9246 など)
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: app.rb:147-154, lib/pj/experiment.rb:109-126; `SCR/api/prod/experiment_types_noparam.b` / 新: routes/api.rb:58-61; `SCR/api/local/track_classes_hg38.b`
- **確認方法**: curl+ソース確認済み (旧の「genome あり・clClass 無し」はソース推定)

### API-07 `/data/sample_types` → `/api/cell_type_classes` (欠落時 400)
- **ページ/機能**: セルタイプクラス別件数
- **旧**: パラメータ無しでも 200 `[{"id":"All cell types","label":"All cell types","count":0}]`
- **新**: `genome`・`track_class` 欠落で 400 `{"error":"genome and track_class required"}`。正常時の本文は 1106 バイトで本番と完全一致
- **分類**: 改良
- **影響度**: 低
- **根拠**: 旧: app.rb:156-163; `SCR/api/prod/sample_types_noparam.b` / 新: routes/api.rb:67-70; `SCR/api/local/cell_type_classes_noparam.b`
- **確認方法**: curl+ソース確認済み

### API-08 `/data/chip_antigen` → `/api/track_subclasses` (`undefined` 番兵は温存、省略時は "All" 行のみ)
- **ページ/機能**: 抗原 (track subclass) 一覧
- **旧**: `clClass=undefined` または `All cell types` で全件、`clClass` 省略時は `where(clClass: nil)` となり `[{"id":"-","label":"All","count":null}]` のみ (本番で 39 バイト確認)
- **新**: 同じ規則 (`cell_type_class` 省略 → 39 バイト、`undefined`/`All cell types` → 6478 バイト、`Blood` → 2959 バイトで本番と一致)
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: 旧: lib/pj/experiment.rb:140-152; `SCR/api/prod/chip_antigen_noclass.b` / 新: lib/models/experiment.rb:157-170; ローカル curl (本節末尾の検証ログ)
- **確認方法**: curl+ソース確認済み
- **備考**: 旧新とも openapi では `clClass`/`cell_type_class` を "required: false" としているが、省略すると実質空の一覧になる。`undefined` という JS 由来の番兵文字列を API 契約として温存しているのは不自然で、省略時に `All cell types` 扱いにする方が API 利用者には親切 (API-06 の `/api/track_classes` は既にそうしている)。

### API-09 `/data/cell_type` → `/api/cell_type_subclasses`
- **ページ/機能**: セルタイプ (subclass) 一覧
- **旧/新**: hg38/Histone/Blood で 15759 バイト完全一致。`clClass`/`cell_type_class` が `undefined`/`All cell types`/省略のときは両方 "All" 行のみ (設計どおり)
- **分類**: 単なる変更
- **影響度**: 低
- **根拠**: `SCR/api/prod/cell_type.b` = `SCR/api/local/cell_type_subclasses.b`; lib/models/experiment.rb:172-183
- **確認方法**: curl+ソース確認済み

### API-10 `/data/exp_metadata.json?expid=` → `/api/experiment?experiment_id=`
- **ページ/機能**: 実験メタデータ
- **旧**: `[{expid, genome, agClass, agSubClass, clClass, clSubClass, title, attributes, readInfo, clSubClassInfo}]` をゲノムごとに 1 件 (SRX018625 は hg38, hg19 の 2 件)、並びは genome 名中の数字の降順 (experiment.rb:49)。`expid` 欠落・不明・GSM は 200 `[]`
- **新**: `[{experiment_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes, read_info, cell_type_subclass_info}]` (SRX018625 は hg38 の 1 件)、並びは config/genomes.yml 順。`experiment_id` 欠落 → 400 JSON、不明/GSM → 200 `[]`
- **分類**: 単なる変更 + データ差分
- **影響度**: 中
- **根拠**: 旧: app.rb:123-124, lib/pj/experiment.rb:34-50; `SCR/api/prod/exp_metadata*.b` / 新: routes/api.rb:89-92, lib/models/experiment.rb:185-191; `SCR/api/local/experiment*.b`
- **確認方法**: curl+ソース確認済み
- **備考**: `attributes` はタブ区切り (`\t`) で両方同じ。新 openapi.yaml:554-585 は「単一オブジェクト」と記述しているが実装は配列 (API-46)。GSM ID の解決は `/view` にしか無い点も旧と同じ (agents.markdown:33 の「GEO sample IDs are accepted where noted」は `/api/experiment` では不可)。

### API-11 `/data/search` → `/api/search` (旧の genome フィルタ不全を修正、offset 追加)
- **ページ/機能**: 全文検索 API
- **旧**: 本番で `q=CTCF&genome=hg38` → `{"total":0,...}`、`q=SRX018625&genome=hg38` → 0 件、同じクエリを `genome` 無しで送ると 1 件ヒットし `"genome":"hg19, hg38"`。原因: FTS テーブルの genome 列に配列を ", " で連結した文字列を格納 (experiment_search.rb:21) し、`genome = 'hg38'` の等値比較で絞る (同:45-47) ため、**genome フィルタは常に空**。空クエリは 0 件。`offset` 無し。`attributes` は `__TAB__` 区切り
- **新**: genome はゲノムごとの行に分割済みで `q=CTCF&genome=hg38` → total 3149 (無指定 6022)。`offset` 対応。空 `q` は全件一覧 (`total` は全件数、experiment_id 順)。`limit` は 1-100 に丸め (非数は 1)。キー snake_case、`attributes` は `__TAB__` 区切りのまま
- **分類**: 改良 (旧バグ修正)
- **影響度**: 高
- **根拠**: 旧: old-app/lib/pj/experiment_search.rb:8-33, 35-82; `SCR/api/prod/search.b` (41 B), `search2_SRX018625.b`, `search3_*.b`, `search4_CTCF.b` / 新: lib/models/experiment_search.rb:94-148; `SCR/api/local/search*.b`
- **確認方法**: curl+ソース確認済み
- **備考**: 旧 UI の /search ページは DataTables で `/data/ExperimentList(_adv).json` を丸ごと読む方式 (search.js:70,138) で `/data/search` を使っていないため、本番でこのバグは表面化していない。新 openapi は `q` を required としているが省略可 (API-46)。

### API-12 `/qvalue_range`・`/data/qval_range.json` → `/api/qval_range`
- **旧/新**: 21 バイト完全一致 `["05","10","20","50"]`。新は `Cache-Control: public, max-age=3600`
- **分類**: 単なる変更 / **影響度**: 低
- **根拠**: app.rb:227-230, 121; routes/api.rb:103-106; `SCR/api/prod/qvalue_range.b`, `SCR/api/local/qval_range.b`
- **確認方法**: curl+ソース確認済み

### API-13 `/data/number_of_lines.json` → `/api/bed_sizes`
- **旧/新**: 同一形状 `{"<genome>,<agClass>,<clClass>,<qval>": <int>}`。4924 件 → 3127 件 (10 ゲノム → 7 ゲノム)。キー中の語彙は旧のまま ("All antigens")
- **分類**: データ差分 / **影響度**: 低
- **根拠**: lib/pj/bedsize.rb:25-32; lib/models/bedsize.rb:11-18; `SCR/api/prod/number_of_lines.b`, `SCR/api/local/bed_sizes.b`
- **確認方法**: curl+ソース確認済み

### API-14 `/data/index_all_genome.json` → `/api/genome_index`
- **旧**: `{"hg38":{"antigen":{"<agClass>":{"<agSubClass>":n}},"celltype":{"<clClass>":{"<clSubClass>":n}}},...}` 10 ゲノム、280626 バイト
- **新**: `{"hg38":{"track":{...},"cell_type":{...}},...}` 7 ゲノム、152154 バイト、`Cache-Control: max-age=3600` + サーバ内 1 時間キャッシュ。hg38 の Histone は 139 サブクラスで一致
- **分類**: 単なる変更 / **影響度**: 中
- **根拠**: lib/pj/experiment.rb:199-222; lib/models/experiment.rb:107-116, 209-230; `SCR/api/prod/index_all_genome.b`, `SCR/api/local/genome_index.b`
- **確認方法**: curl+ソース確認済み

### API-15 `/data/colo_analysis.json?genome=` → `/api/colo_index?genome=` ("-" 除去、400)
- **旧**: `{"hg38":{"antigen":{"ADAR":["-"],...},"cellline":{"-":[114 antigens],"Blood":[...]}}}`。cell_list が "-" (データ無し) の行を split すると `["-"]` になるため、hg38 で 114 antigen が `["-"]`、cellline に `"-"` キーが混入。genome 無しは 200 `{"":{}}`
- **新**: `{"hg38":{"track":{...1653},"cell_type":{...20}}}`。"-" 行を除外 (差分の 114 件は全て旧の `["-"]` 行であることを確認)。genome 無しは 400
- **分類**: 改良 / **影響度**: 中
- **根拠**: 旧: lib/pj/analysis.rb:33-51; `SCR/api/prod/colo_analysis.b` / 新: lib/models/analysis.rb:43, 76-92; `SCR/api/local/colo_index.b`; python 照合 (本節末尾)
- **確認方法**: curl+ソース確認済み

### API-16 `/data/target_genes_analysis.json` → `/api/target_genes_index`
- **旧/新**: 同一形状。hg38 (1766) / mm10 (869) / rn6 (67) / dm6 (263) / ce11 (162) / sacCer3 (67) の名前集合は完全一致。新は TAIR12 (77) を追加、hg19/mm9/dm3/ce10 を削除
- **分類**: データ差分 / **影響度**: 低
- **根拠**: `SCR/api/prod/target_genes_analysis.b`, `SCR/api/local/target_genes_index.b`; lib/models/analysis.rb:105-114
- **確認方法**: curl+ソース確認済み

### API-17 `/data/index_subclass.json` の廃止
- **旧**: `?genome=&agClass=&clClass=&type=ag|cl` で `{"<subclass>": count}` (819 バイト)。旧 JS からは参照されていない (grep 0 件)
- **新**: 無し (最寄りは `/api/track_subclasses` / `/api/cell_type_subclasses` / `/api/genome_index`)
- **分類**: 機能削除 / **影響度**: 低
- **根拠**: app.rb:132-137, lib/pj/experiment.rb:169-187; `SCR/api/prod/index_subclass.b`
- **確認方法**: curl+ソース確認済み

### API-18 一括ダンプ `/data/ExperimentList.json`・`/data/ExperimentList_adv.json` の廃止
- **旧**: 本番では nginx が静的ファイルとして配信 (ETag `"68faf33b-2a11475"`、`Cache-Control: public, max-age=3600`、44,110,965 B / 161,647,706 B、2025-10-24 版)。ルート直下 `/ExperimentList.json` も同じファイル。旧 MCP の検索と旧 /search ページの唯一のデータ源
- **新**: `/data/...` は 404。ルート直下 `/ExperimentList.json` (44MB) `/ExperimentList_adv.json` (170MB, 2026-09-13 版) は作業ツリーの bind mount では 200 だが、`.dockerignore`:11-12 で本番イメージから除外されるため本番では 404 になると推定。llms.txt:36 は「/api/search が bulk JSON dump を置き換える」と明記
- **分類**: 機能削除 (意図的) / **影響度**: 高 (メタデータ一括取得の用途)
- **根拠**: `SCR/api/prod/data_ExperimentList_json.h`, `ExperimentList_static.h`; `SCR/api/local/old_data_ExperimentList.h` (404), `static_ExperimentList_json.h` (200); .dockerignore:11-12
- **確認方法**: curl+ソース確認済み (本番イメージでの 404 はソース推定)
- **備考**: 一括取得の代替は `/api/search?q=&genome=hg38&limit=100&offset=N` を 100 件ずつ 4,500 回叩くこと (453,932 件) になり、利用者にも運用にも負担。データサーバ (chip-atlas.dbcls.jp/data/metadata/) へのリンクを llms.txt で案内するか、圧縮ダンプを残す方が現実的。

### API-19 未知 `/data/<x>.json` の応答: 200 `null` → 404 JSON
- **旧**: `/data/nonexistent.json` → 200 `null` (case 文に該当なしで `JSON.dump(nil)`)
- **新**: `/api/nonexistent` → 404 `{"error":"Not found"}`
- **分類**: 改良 / **影響度**: 低
- **根拠**: app.rb:113-145; routes/pages.rb:152-164; `SCR/api/prod/unknown_json.b`, `SCR/api/local/api_unknown.b`
- **確認方法**: curl+ソース確認済み

### API-20 POST `/browse` → GET/POST `/api/igv_url`
- **旧**: JSON body を Content-Type に関係なく `JSON.parse` (app.rb:243-249)。`{"url":"http://localhost:60151/load?genome=hg38&file=<bed url>"}`。`igv` キーで IGV の URL を差し替え可
- **新**: GET はクエリ (`genome`,`track_class` 必須、他は任意)、POST は `application/json` 必須で `condition` オブジェクト必須。応答は同型。GET では `igv` を渡せない (`condition_from_params` が condition しか組まない)。Annotation tracks で存在しない subclass を指定すると `Bedfile.get_trackname` の `NotFound` が未捕捉で 500 (旧も `NameError` が未捕捉で 500)
- **分類**: 単なる変更 / **影響度**: 中
- **根拠**: 旧: app.rb:243-249, lib/pj/location.rb:45-64 / 新: routes/api.rb:23-37, 133-142, lib/services/location_service.rb:22-31; `SCR/api/local/igv_url*.b`, `post_igv_url.b`; ローカル curl (Annotation tracks/NOPE → 500 `ChipAtlas::Bedfile::NotFound`)
- **確認方法**: curl+ソース確認済み (旧 POST は本番未実行、ソース推定)
- **備考**: `igv_browsing_url` の Annotation 分岐だけ `rescue NotFound` が無い (location_service.rb:26)。`{"url":null}` を返す `archive_url` と揃えるべき。

### API-21 POST `/download` → GET/POST `/api/download_url` (拡張子探索付き)
- **旧**: `{"url":"https://chip-atlas.dbcls.jp/data/hg38/assembled/<filename>.bed"}` (拡張子 `.bed` 固定、該当なしは `{"url":null}`)。応答はリダイレクトではなく JSON
- **新**: 同型。ファイル名は bedfiles テーブル由来で同じ (`His.Bld.05.H3K4me3.AllCell.bed`)。拡張子は `.bed` → `.bed.gz` の順にアーカイブへ HEAD して決定し 1 時間キャッシュ (未確認時 5 秒)。旧キー名 (`agClass` 等) の condition を POST すると 200 `{"url":null}` (エラーにならない)。`qval=5` (旧 spec の値) も `{"url":null}`
- **分類**: 改良 (gzip 移行対応) / **影響度**: 中
- **根拠**: 旧: app.rb:251-258, lib/pj/location.rb:21-43 / 新: routes/api.rb:144-153, lib/services/location_service.rb:80-86, bed_extension_resolver.rb:27-32, 69-89; `SCR/api/local/download_url*.b`, `post_download_url*.b`
- **確認方法**: curl+ソース確認済み
- **備考**: 1 リクエストあたり最大 2 回の外部 HEAD (各 2 秒タイムアウト) が発生するため、アーカイブ停止時は応答が最大 4 秒遅れ、`.bed` を「推定」で返す。未知キーを黙って無視する点は、移行期の利用者にとって原因が分かりにくい (400 で `unknown key agClass; use track_class` と返す方が親切)。

### API-22 POST `/colo?type=` → GET `/api/colo` + `/api/colo/download`
- **旧**: `type=submit|tsv|gml` に応じて dbcls 上の `<antigen>.<cellline>.html` / `.tsv` / `<cellline>.gml` の URL を返すだけ (存在確認なし)。cellline の空白は `_` に置換、antigen は無加工
- **新**: `/api/colo?genome&track&cell_type` は TSV を取得して `{columns:[...21], rows:[[str,str,str,num...]], total:3862, genome, track, cell_type}` (Average 降順、全行 407KB、サーバ側キャッシュ無し、毎回 dbcls から 263KB 取得)。`/api/colo/download?format=tsv|gml` はファイルをアプリ経由で配信 (`Content-Disposition: attachment; filename="STAT3.Blood.tsv"`; gml は `application/xml`、実体は `Blood.gml` 33,228,517 B を `STAT3.Blood.gml` の名前で配信)。**dbcls 側の URL は API からは得られない**。HTML 結果ページ (`.html`) への導線は無し
- **分類**: 単なる変更 + 新機能 (JSON 化) / **影響度**: 中
- **根拠**: 旧: app.rb:280-286, lib/pj/location.rb:70-82, colo.js:184-196 / 新: routes/api.rb:158-187, lib/services/colo_tsv.rb:100-109, location_service.rb:34-40, 64-70, data_proxy.rb:55-69; `SCR/api/local/colo.b`, `colo_dl.h`, `colo_dl_gml.h`
- **確認方法**: curl+ソース確認済み
- **備考**: `DataProxy.fetch_live` は `response.body` を丸ごとメモリに載せる (ストリーミング無し)。33MB の GML を複数クライアントが同時に取ると puma スレッド 5 本 × 33MB がヒープに乗る。gml は旧のように dbcls への直リンク (302) を返す方が軽い。

### API-23 POST `/target_genes?type=` → GET `/api/target_genes` + `/api/target_genes/download`
- **旧**: `<antigen>.<distance>.html|tsv` の URL を返す
- **新**: TSV を解析して `{columns, rows, total, offset, limit}` を返す。`sort` (列名; 不正は 400), `order`, `offset`, `limit` (既定 50、上限 500), `q` (遺伝子名部分一致、200 文字で切詰め)。5 分 TTL・150MB 上限のサーバ内キャッシュ。`/download?format=tsv` はプロキシ配信 (`CTCF.5.tsv`, 47KB)
- **分類**: 新機能 / **影響度**: 中
- **根拠**: 旧: app.rb:308-314, location.rb:88-99 / 新: routes/api.rb:192-227, lib/services/target_genes_tsv.rb:61-75, 136-158; `SCR/api/local/target_genes*.b`, `target_genes_dl.h`
- **確認方法**: curl+ソース確認済み
- **備考**: dm6 の括弧付き名 (`E(z)`, `Su(var)3-9`) は `%28`/`%29` にエンコードされ、dbcls が正しく解決することを確認 (200)。

### API-24 `/colo_result?base=`・`/target_genes_result?base=` (旧は 500) → アプリ内結果ページ
- **旧**: `remotefile_available?(@iframe_url)` を呼ぶが、このメソッドは `PJ::FastQC` のインスタンスメソッド (lib/pj/fastqc.rb:100) で app には未定義 → 本番で `500 <h1>Internal Server Error</h1>` (両ルートとも確認)。旧 UI はこのルートを使わず dbcls へ直接遷移
- **新**: `/colo_result?genome=&track=&cell_type=`、`/target_genes_result?genome=&track=&distance=` のアプリ内ページ (JS が `/api/colo` / `/api/target_genes` を呼ぶ)
- **分類**: 改良 / **影響度**: 低
- **根拠**: 旧: app.rb:288-296, 316-324; `SCR/api/prod/colo_result.b`, `tg_result.b` (500) / 新: routes/pages.rb:62-82, frontend/pages/colo-result.ts:53-58, colo.ts:168
- **確認方法**: curl+ソース確認済み

### API-25 `/wabi_endpoint_status` → `/status` + `/jobs/available`
- **旧**: 本文 `chipatlas` (WABI が応答した場合) または空、`text/html;charset=utf-8`、毎回 WABI へ GET (3 秒タイムアウト)
- **新**: `/status` → `{"services":{"data_server":"ok","wabi":"ok","wes":"not_checked"},"features":{"peak_browser":"ok","colo":"ok","target_genes":"ok","search":"ok","enrichment_analysis":"ok","diff_analysis":"unavailable"}}` (`Cache-Control: public, max-age=30`、各サービスの HEAD 結果を 60 秒キャッシュ)。`/jobs/available?type=` → `{"backend":"wabi","available":true}` / `{"backend":null,"available":false}` (`type` 不明でも 200)
- **分類**: 単なる変更 / **影響度**: 中
- **根拠**: 旧: app.rb:30-38, 455-457; `SCR/api/prod/wabi_endpoint_status.b` / 新: routes/health.rb:27-40, lib/services/service_monitor.rb:12-63, routes/jobs.rb:45-48; `SCR/api/local/status.b`, `jobs_available*.b`
- **確認方法**: curl+ソース確認済み
- **備考**: 新 openapi.yaml:196-210 / llms.txt:77 は `/status` を「data_server/wabi/wes の boolean + feature_status」と記述しており実装と不一致 (API-46/47)。

### API-26 POST `/wabi_chipatlas` → POST `/jobs/submit`
- **旧**: form-urlencoded でも JSON でも受け付け、WABI の全フィールド (address, format, result, sbatchOptions を含む) をクライアントが送る。成功時 `{"requestId":"wabi_chipatlas_..."}` (Content-Type は text/html)。WABI 停止時は 503 (本文なし)。応答解析失敗は `not_found` へ 302 → 404
- **新**: `application/json` のみ、`{"type":"enrichment_analysis","params":{...WABI 名...}}`。運用フィールドは wabi_service.rb:19-24 がサーバ側で上書き付与 (クライアントの値は無視)。成功時 `{"backend":"wabi","job_id":"..."}` (routes/jobs.rb:59)、バックエンド無し → 503 `{"error":"No compute backend available","retry":false}`、拒否 → 502、JSON 無し → 400。WABI 停止時は WES (ea.chip-atlas.org) へフォールバック
- **分類**: 単なる変更 / **影響度**: 高 (非互換)
- **根拠**: 旧: app.rb:477-501 / 新: routes/jobs.rb:51-75, lib/services/compute_router.rb:50-60, wabi_service.rb:19-24, 89-95; `SCR/api/local/post_jobs_submit_*.b`
- **確認方法**: curl+ソース確認済み (成功応答はソース推定; 実ジョブ投入はしていない)
- **備考**: 新 openapi.yaml:1279-1291 は成功応答を `{id, backend}` と記述 (実装は `job_id`) (API-46)。`params` の中身が WABI の camelCase のままである点は openapi.yaml:223-229 に明記されており正確。

### API-27 diff_analysis のジョブ投入が常に 503
- **旧**: `/wabi_chipatlas` に `antigenClass=dmr|diffbind` で投入 (UI から利用可能; 本番で投入可能かは未検証)
- **新**: `ComputeRouter::JOB_TYPE_BACKENDS['diff_analysis'] = []` のため `/jobs/available?type=diff_analysis` → `{"backend":null,"available":false}`、`/jobs/submit` `type=diff_analysis` → 503、`/status` → `diff_analysis:"unavailable"`
- **分類**: 機能削除 (意図的; コメントは「WABI が現在 diff analysis を受け付けない」)
- **影響度**: 高
- **根拠**: lib/services/compute_router.rb:9-24; routes/health.rb:31-37; `SCR/api/local/post_jobs_submit_diff.b`, `jobs_available_diff.b`, `status.b`
- **確認方法**: curl+ソース確認済み (本番の diff 投入可否は未検証)
- **備考**: llms.txt:56, 95 と openapi.yaml:219-222, 321-374 は diff_analysis を投入可能な type として説明しており、利用者は 503 の理由を知る術がない。ドキュメント側に「現在停止中」を明記するか、`/jobs/available` の応答に理由 (`reason: "no backend configured"`) を足すべき。

### API-28 GET `/wabi_chipatlas?id=` → GET `/jobs/:id/status?backend=`
- **旧**: dtn1 に ping し、`?info=result&format=html` が 200 なら `finished`、それ以外 `running`、ping 失敗で `server unavailable` (テキスト、text/html)
- **新**: `?info=status` の `status:` 行を返す `{"backend":"wabi","job_id":"...","status":"finished"|"running"|...,"retry":true}`。不明 ID は `"status":"unknown"` (200)。`backend` 欠落/不正 → 400 `{"error":"Invalid backend"}`、`id` が `[\w-]+` 以外 → 400、backend 停止 → 503
- **分類**: 改良 / **影響度**: 中
- **根拠**: 旧: app.rb:460-474 / 新: routes/jobs.rb:10-19, 78-91, lib/services/wabi_service.rb:97-137; `SCR/api/local/jobs_status_*.b`, `jobs_badid.b`
- **確認方法**: curl+ソース確認済み (旧の応答文字列は本番未実行、ソース推定)
- **備考**: openapi.yaml:375-391 の JobStatus (`id`, enum queued/running/completed/failed) は実装 (`job_id`, WABI の語 "finished" 等 + `retry`) と不一致 (API-46)。

### API-29 `*_log?id=` → `/jobs/:id/log?backend=` (404 が HTML のまま)
- **旧**: 成功時ログ本文 (text/html)、失敗時 `status 404` + "Log file not available yet" のつもりだが Sinatra の `not_found` ハンドラ (app.rb:447) が HTML 404 ページで上書き (本番で 6513 B の HTML を確認)
- **新**: 成功時 `text/plain`。失敗時 `halt 404, 'Log not available yet'` だが、pages.rb:152-164 の not_found は Content-Type が `application/json` の時だけ本文を温存するため、ここでも HTML 404 ページ (7846 B) に置き換わる
- **分類**: 単なる変更 (要修正候補) / **影響度**: 低
- **根拠**: 旧: app.rb:374-390, 447-449; `SCR/api/prod/diff_log.b` / 新: routes/jobs.rb:107-122, routes/pages.rb:152-164; `SCR/api/local/jobs_log.b`
- **確認方法**: curl+ソース確認済み
- **備考**: `halt 404, json_response({error:'Log not available yet'})` にすれば JSON で返る。openapi.yaml:1387-1397 は 200 応答を JSON `{log}` としているが実装は text/plain (API-46)。

### API-30 `/jobs/:id/result` (新規)
- **新**: `{"backend":"wabi","job_id":"abc123","urls":{"html":"https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/abc123?info=result&format=html","tsv":"...&format=tsv"}}`、`type=diff_analysis` では `{"urls":{"zip":"...&format=zip"}}`。`type` 不正 → 400。存在確認はしない (未知 ID でも 200)
- **分類**: 新機能 / **影響度**: 低
- **根拠**: routes/jobs.rb:27-33, 94-104, compute_router.rb:78-93; `SCR/api/local/jobs_result*.b`
- **確認方法**: curl+ソース確認済み

### API-31 POST `/diff_analysis_estimated_time` → POST `/jobs/estimated_time`
- **旧/新**: 同一計算式・同一応答 `{"minutes": 8}` / `{"minutes": null}` (analysis 不正時)。新は JSON 必須 (無しは 400)
- **分類**: 単なる変更 / **影響度**: 低
- **根拠**: app.rb:392-417; routes/jobs.rb:125-134; `SCR/api/local/post_estimated_time*.b`
- **確認方法**: curl+ソース確認済み

### API-32 `/api/remoteUrlStatus` → `/api/remote_url_status` (契約変更、SSRF 封じ)
- **旧**: 任意 URL を `Net::HTTP.get_response` (本文全取得) し、ルートの戻り値が Integer なので Sinatra が **HTTP ステータスコードとして採用、本文は空** (本番: 200 / content-length 0)。`url` 無しは 500。旧 JS は `transport.status === 200` で判定 (experiment.js:96-104)
- **新**: 許可ホスト (`chip-atlas.dbcls.jp`, `dtn1.ddbj.nig.ac.jp` と各サブドメイン) 以外は 400 "Invalid or disallowed URL"。HEAD (5s/10s タイムアウト)。**本文に "200" 等の数字文字列、HTTP は常に 200** (`text/html`)。上流応答時のみ `Cache-Control: public, max-age=3600`、例外時は本文 "500" (キャッシュ無し)
- **分類**: 改良 (セキュリティ) だが契約は非互換 / **影響度**: 中
- **根拠**: 旧: app.rb:503-505; `SCR/api/prod/remoteUrlStatus.h` (200, length 0), `remoteUrlStatus_noparam.h` (500) / 新: routes/api.rb:8-19, 231-254; `SCR/api/local/remote_url_status*.b`
- **確認方法**: curl+ソース確認済み

### API-33 `/health` の checks キー変更
- **旧**: `{"status":"ok","checks":{"database":"ok","config":"ok"}}`
- **新**: `{"status":"ok","checks":{"database":"ok","experiments":"ok"}}` (`experiments` は件数 > 0 なら ok、0 なら "empty" だが healthy 判定には使わない)
- **分類**: 単なる変更 / **影響度**: 低
- **根拠**: app.rb:194-220; routes/health.rb:8-24; `SCR/api/prod/health.b`, `SCR/api/local/health.b`
- **確認方法**: curl+ソース確認済み

### API-34 `/style.css` (SASS 動的コンパイル) の廃止
- **旧**: `get "/:source.css"` が `views/*.sass` をリクエスト時にコンパイル (本番 `/style.css` 4172 B, text/css)
- **新**: 404。CSS は `/css/style.css` (静的 18461 B)
- **分類**: 機能削除 (意図的) / **影響度**: 低
- **根拠**: app.rb:109-111; `SCR/api/prod/stylecss.h`, `SCR/api/local/old_style_css.h`
- **確認方法**: curl+ソース確認済み

### API-35 `/view` の入力検証
- **旧**: `id` 無し → `nil.upcase` で 500。`?id=GSM469863` → 302 `/view?id=SRX018625` (ExperimentList.json 由来のハッシュ)
- **新**: `id` 無し → 400 `{"error":"id parameter required"}` (HTML ページなのに JSON)。GSM → 302 (FTS テーブルの geo_id 検索)
- **分類**: 改良 / **影響度**: 低
- **根拠**: app.rb:260-268; routes/pages.rb:27-54, lib/models/experiment_search.rb:89-92; `SCR/api/prod/view_noid.h`, `SCR/api/local/view_noid.b`, `view_gsm.h`
- **確認方法**: curl+ソース確認済み

### API-36 結果ページ URL の `api=` → `backend=`
- **旧**: 投入後 `/enrichment_analysis_result?id=<requestId>&api=wabi&title=...&calcm=...` へ遷移 (diff は `&title=` 以降)
- **新**: `/enrichment_analysis_result?id=<job_id>&backend=wabi&title=...&calcm=...`。`backend` が無い URL はエラー状態を表示 (result-page-params.ts:33-36)
- **分類**: 単なる変更 / **影響度**: 低〜中 (旧 URL を保存・生成しているスクリプトやブックマークが壊れる)
- **根拠**: enrichment_analysis.js:730-733, 777-779; diff_analysis.js:182-184; frontend/pages/enrichment-analysis.ts:783-786, diff-analysis.ts:376-379; frontend/components/result-page-params.ts:4-9
- **確認方法**: ソース推定 (要ブラウザ確認: 旧 URL 形式を新版で開いた時の表示)
- **備考**: `api=` を `backend=` の別名として読むだけで互換になる。

### API-37 404 の形式: `/api/*` は JSON
- **旧**: 全ての 404 が HTML ページ (`x-cascade: pass`)
- **新**: `/api/` 配下の未知パスは `{"error":"Not found"}` (application/json)。それ以外は HTML
- **分類**: 改良 / **影響度**: 低
- **根拠**: routes/pages.rb:152-164; `SCR/api/local/api_unknown.b`, `notfound.b`
- **確認方法**: curl+ソース確認済み

### API-38 エラー本文の統一 (JSON `{"error": ...}`)
- **旧**: パラメータ欠落は 200 + `null` / `[]` / count 0、内部例外は 500 `<h1>Internal Server Error</h1>`、WABI 停止は 503 空本文
- **新**: 400 (`genome parameter required` 等)、404 (`Colocalization data not found`)、502 (解析不能/バックエンド拒否)、503 (`No compute backend available`, `retry:false`)、`Invalid JSON` / `No JSON body` (400) をすべて JSON で返す。ただし `/api/remote_url_status` と `/jobs/:id/log` の失敗はテキスト/HTML (API-29, 32)、未捕捉例外は 500 (API-53)
- **分類**: 改良 / **影響度**: 中
- **根拠**: routes/api.rb 各 `halt`、lib/middleware/json_body_parser.rb:17-29; `SCR/api/local/*_noparam.b`, `colo_404.b`, `post_download_url_badjson.b`
- **確認方法**: curl+ソース確認済み

### API-39 Cache-Control ヘッダ
- **旧**: アプリは付与しない。本番 nginx は静的ファイル (`/js/`, `/css/`, `/images/`) に `expires` を設定し、`/data/*` 応答に `x-cache: HIT|MISS|EXPIRED` が付く (proxy cache が本番 nginx に存在)。ただしリポジトリの old-app/config/nginx/chip-atlas.conf に proxy_cache の記述は無く、本番設定はリポジトリと乖離している (推定)。`/data/ExperimentList.json` は nginx が静的配信 (ETag, max-age=3600)
- **新**: `/api/genomes`, `/api/track_classes` (無引数), `/api/target_genes_distances`: `public, max-age=86400`; `/api/stats`, `/api/genome_index`, `/api/qval_range`, `/api/bed_sizes`, `/api/colo_index`, `/api/target_genes_index`: `max-age=3600`; `/status`: `max-age=30`; `/api/remote_url_status`: 上流応答時のみ 3600。件数付き分類 API・search・experiment・colo・target_genes・download_url・igv_url・health・jobs は無指定。config/nginx/chip-atlas.conf に proxy_cache 無し
- **分類**: 改良 / **影響度**: 低
- **根拠**: `SCR/api/prod/*.h` (x-cache), old-app/config/nginx/chip-atlas.conf; routes/api.rb:49, 53, 62, 85, 104, 109, 117, 122, 127, 248, routes/health.rb:28; `SCR/api/local/*.h`
- **確認方法**: curl+ソース確認済み (本番 nginx 設定は推定)
- **備考**: 新版でも本番 nginx に proxy cache を残すなら、`Cache-Control` を付けた応答が nginx 側でも 1 時間キャッシュされる。データ更新直後に古い `genome_index` が最大 2 時間 (アプリ内 1h + nginx 1h) 残り得る。

### API-40 CORS: 旧新とも無し
- **旧/新**: `Origin` を付けた GET でも `Access-Control-Allow-Origin` は付かない。OPTIONS は 404。rack-cors 等の gem は両方の Gemfile に無い
- **分類**: 単なる変更 (なし) / **影響度**: 低 (ブラウザ内の第三者アプリからは従来どおり呼べない)
- **根拠**: `SCR/api/prod/cors.h`, `cors_options.h`; `SCR/api/local/cors.h`, `cors_options.h`; Gemfile 両方
- **確認方法**: curl+ソース確認済み

### API-41 Host 認可: 旧新とも `.chip-atlas.org` のみ
- **旧**: `Host: evil.example.com` → 403 `Host not permitted` (rack-protection HostAuthorization)
- **新**: 同設定 (app.rb:70-72)。ローカルは RACK_ENV=development のため Sinatra 4.2 の既定 (localhost 系のみ) で同様に 403
- **分類**: 単なる変更 (なし) / **影響度**: 低
- **根拠**: old-app/app.rb:87-89; app.rb:70-72; `SCR/api/prod/badhost.b`, `SCR/api/local/badhost.b`; Sinatra 4.2.1 (両 Gemfile.lock)
- **確認方法**: curl+ソース確認済み
- **備考**: IP 直打ちや別 CNAME からの API 呼び出しは旧新とも 403。

### API-42 JSON 整形・Content-Type
- **旧/新**: 両方コンパクト JSON (`JSON.dump`/`JSON()` → `JSON.generate`)、`content-type: application/json` (charset 無し)。テキスト応答は旧 `text/html;charset=utf-8` (wabi_endpoint_status 等)、新は `/jobs/:id/log` のみ `text/plain`、`/api/remote_url_status` は `text/html`。`x-content-type-options: nosniff` は両方 (rack-protection)。HTML 応答の `x-frame-options: SAMEORIGIN`, `x-xss-protection` も両方
- **分類**: 単なる変更 (なし) / **影響度**: 低
- **根拠**: `SCR/api/prod/*.h`, `SCR/api/local/*.h`
- **確認方法**: curl 確認済み

### API-43 `count: null` の扱い
- **旧**: 分類 API で該当データが無いカテゴリは `count: null` (例: hg38/Blood の "Annotation tracks")。パラメータ欠落時は全項目 null。"-"/"All" 行は常に null
- **新**: 同じ。ただし `/api/track_classes` を無引数で呼ぶと `count` キー自体が無い (`[{id,label}]`)。件数付きでは旧と同一 (hg38/Blood の Annotation tracks が null)
- **分類**: 単なる変更 / **影響度**: 低
- **根拠**: `SCR/api/prod/experiment_types_blood.b` = `SCR/api/local/track_classes_blood.b`; lib/models/experiment.rb:135-137, 159, 173
- **確認方法**: curl+ソース確認済み
- **備考**: 新 openapi の ClassificationItem は `count` を optional/nullable としており、この点は正確。

### API-44 配列の並び順
- **分類 API**: 旧新とも SQL の GROUP BY 順 (SQLite では実質アルファベット順)。hg38/Histone の cell_type_classes 26 件、track_subclasses (Blood) 64 件、cell_type_subclasses 全件が順序込みで一致
- **`/api/experiment`**: 旧 genome 数字降順 → 新 genomes.yml 順 (API-10)
- **`/api/search`**: 旧新とも FTS5 rank 順。新の空クエリは experiment_id 順
- **`/api/colo` rows**: Average 降順 (旧 HTML 結果ページの既定と同じ)。`/api/target_genes` rows: `sort` 既定は `<track>|Average` 降順
- **`/api/genomes` / `/api/genome_index` / `/api/stats.by_genome`**: genomes.yml 順 / genomes.yml 順 / SQL 順 (TAIR12 が先頭)
- **分類**: 単なる変更 / **影響度**: 低
- **根拠**: python 照合 (本節末尾), lib/models/experiment.rb:190, experiment_search.rb:104-146, colo_tsv.rb:106, target_genes_tsv.rb:147-149
- **確認方法**: curl+ソース確認済み

### API-45 特殊文字のエンコード
- **旧**: `colo_url`/`target_genes_url` は antigen を無加工で URL に埋め込み、cellline の空白のみ `_` に置換 (location.rb:70-99)
- **新**: `URI.encode_www_form_component` で track と cell_type (空白→`_` 置換後) をエンコード (location_service.rb:64-70)。空白は `+` に、`/` は `%2F` に、`(` は `%28` になる。コンテナ内で確認: `RNA polymerase II` → `.../colo/RNA+polymerase+II.Blood.tsv`、`ESR1/ESR2` → `ESR1%2FESR2.K-562.tsv`
- **現データへの影響**: 全 7 ゲノムの colo_index と target_genes_index を走査した結果、空白・`/`・`+`・`&`・`%`・`#`・`?` を含む track 名は 0 件 (括弧付きは dm6 に 15 件、`%28` で dbcls が正しく解決することを 200 で確認)。cell_type は "Digestive tract" 等の空白のみで `_` 置換される
- **分類**: 単なる変更 (潜在リスク) / **影響度**: 低
- **根拠**: python 走査 (本節末尾); `docker exec chip-atlas-local ruby -e ...` の出力; ローカル curl `/api/target_genes?genome=dm6&track=E(z)&distance=5` → 200
- **確認方法**: curl+ソース確認済み
- **備考**: 将来 track 名に空白が入ると `+` がパス中のリテラルになり dbcls で 404 になる。パスセグメント用には `ERB::Util.url_encode` (空白→`%20`) が適切。

### API-46 openapi.yaml: 新 spec と実装の不一致 (spot-check 13 点) と旧 spec の誤り
- **ページ/機能**: `/openapi.yaml`
- **旧 (v1.0.0, 11 paths)**: 実装との差: (a) `qval` enum "1,5,10,50,100" (実際 "05,10,20,50"; llms.txt:46 自身が正しい値を書いている); (b) GenomeAssembly に存在しない `mm39`; (c) `/data/search`, `/qvalue_range`, `/data/index_all_genome.json`, `/data/number_of_lines.json`, `/data/index_subclass.json`, `/browse`, `/colo`, `/target_genes`, WABI 系が未記載; (d) `/data/list_of_genome.json` の example は正確; (e) `/download` example のファイル名 `H3K4me3.Blood.5.bed` は実在形式 (`His.Bld.05.H3K4me3.AllCell.bed`) と異なる
- **新 (v2.0.0, 26 paths)**: ローカル実測との差:
  1. `/api/genomes` (openapi.yaml:396-418): 「string 配列」→ 実装はオブジェクト `{id: label}`
  2. `/api/experiment` (554-585): 「単一の ExperimentMetadata」→ 実装は配列
  3. `/status` (196-210, 1207-1228): `data_server/wabi/wes` boolean + `feature_status` → 実装は `services:{...:"ok"|"down"|"not_checked"}`, `features:{...}`
  4. `/jobs/submit` 200 (1279-1291): `{id, backend}` → 実装 `{backend, job_id}`
  5. `/jobs/{id}/status` (375-391, 1305-1331): `{id, status(queued|running|completed|failed), backend}` → 実装 `{backend, job_id, status:"finished"|"running"|…|"unknown", retry}`; 400/503 応答未記載
  6. `/jobs/{id}/result` (1333-1365): `{result_url}` → 実装 `{backend, job_id, urls:{html,tsv}|{zip}}`; `type` パラメータ未記載
  7. `/jobs/{id}/log` (1367-1397): JSON `{log}` → 実装 `text/plain` (404 は HTML)
  8. GenomeAssembly enum (116-127): `TAIR10` → 実装 `TAIR12`
  9. TrackClass enum (51-69): `CUT&Tag`, `CUT&RUN` を含み `Annotation tracks` を含まない → 実装は逆 (`/api/track_classes` の 8 件、`/api/stats.by_track_class`)
  10. `/api/search` `q` required: true (597-603) → 省略可 (全件一覧)
  11. `/api/download_url` example (847) `Histone.H3K4me3.Blood.-.05.bed` → 実際 `His.Bld.05.H3K4me3.AllCell.bed`; `/api/igv_url` example (879) `https://igv.org/app/?sessionURL=` → 実際 `http://localhost:60151/load?...`
  12. `/api/colo` example (907-910, 949-955) の `cell_type: K-562` は cell_type_subclass であり、colo の cell_type は class (Blood 等) なので索引に無く 404 になる (索引からの推定、未実行)
  13. 未記載: `/health`, POST `/jobs/estimated_time`, POST `/api/igv_url`, POST `/api/download_url`, `/api/remote_url_status` (「内部」とコメント)、`/jobs/available` の `type` 省略可
  一致確認済み: `/api/track_classes` (count 付き), `/api/cell_type_classes`, `/api/track_subclasses`, `/api/cell_type_subclasses`, `/api/search` の応答形状 (ただし SearchResult が参照する ExperimentMetadata に `sra_id`/`geo_id` が無く、逆に search が返さない `read_info` 等を含む), `/api/qval_range`, `/api/colo_index` (additionalProperties のみ), `/api/target_genes_index`, `/api/target_genes_distances`, `/api/colo` の columns/rows/total, `/api/target_genes` の全パラメータ (sort/order/offset/limit/q と 400/404/502), `/api/colo/download`, `/api/target_genes/download`, `/jobs/submit` の 503/502 本文
- **分類**: 退行 (要修正)
- **影響度**: 高 (機械可読 spec からクライアントを生成すると 7 エンドポイントで型不一致)
- **根拠**: public/openapi.yaml (行番号は本文), old-app/public/openapi.yaml:75-90, 165-175; `SCR/api/local/genomes.b`, `experiment.b`, `status.b`, `jobs_status_wabi.b`, `jobs_result.b`, `jobs_log.h`, `track_classes.b`, `search_empty.b`; `SCR/api/prod/qvalue_range.b`
- **確認方法**: curl+ソース確認済み

### API-47 llms.txt の誤記
- **旧**: "GET /search performs full-text search" (llms.txt:56; 実際は `/data/search`)、"over 1M experiments" (本番 `number_of_experiments` は 433,000)
- **新**: `/api/` 系に更新済みで、エンドポイント一覧・snake_case・ページング・データ構成の説明は概ね正確。誤り: (a) L27, L63 ゲノム `TAIR10` (実際 `TAIR12`); (b) L3, L63 に `CUT&Tag`, `CUT&RUN` (track_class に存在しない); (c) L77 `/status` は「data_server, wabi, wes booleans と feature_status」(実際 `services`/`features` の文字列); (d) L47-48 colo の例 `cell_type=K-562` (class ではなく subclass; 索引に無いため 404 になると推定); (e) L3 "over 1M experiments" (実際 454,476); (f) L56/L95 diff_analysis を投入可能と説明 (現状常に 503); (g) L27 `/api/genomes` を「available genome assemblies: hg38, …」とだけ書き、オブジェクトであることに触れていない
- **分類**: 退行 (要修正) / **影響度**: 中 (LLM エージェントがこれを読んで誤った呼び出しをする)
- **根拠**: public/llms.txt:3, 27, 47-48, 56, 63, 77, 95; `SCR/api/local/genomes.b`, `stats.b`, `status.b`, `colo_index.b` (cell_type キー 20 件に K-562 なし)
- **確認方法**: curl+ソース確認済み

### API-48 `/agents` ページ
- **旧**: MCP 節 (インストール、設定 JSON、10 ツールのリファレンス) + HTTP API 表 (`/data/*`, POST `/download`) + ワークフロー。Q-value を "1, 5, 10, 50, 100" と誤記 (agents.markdown:51)
- **新**: MCP 節削除、`/api/` 表に置換、`/api/genomes` が object であることを明記 (正確)、`llms.txt` へのリンク追加、GET/POST の説明、URL エンコードの注意。誤り: `TAIR10` (L26)、`CUT&Tag`/`CUT&RUN` (L27, L130)、colo の例 `cell_type=K-562` (L74-75)、`/jobs/submit` で diff を投入可能とする説明 (L87)
- **分類**: 単なる変更 (誤記は要修正) / **影響度**: 中
- **根拠**: old-app/views/agents.markdown:9-36, 51, 135-153; views/agents.markdown:13-16, 26-27, 45, 74-75, 87, 130; `SCR/api/prod/agents.b`, `SCR/api/local/agents.b` (文字列出現数の照合)
- **確認方法**: curl+ソース確認済み (描画は要ブラウザ確認)

### API-49 robots.txt は同一 (死にパスを Disallow)
- **旧/新**: バイト一致。`Disallow: /api /data /view /browse /download /wabi_chipatlas`。新版で実在するのは `/api` `/view` のみ。`/jobs` `/status` `/api/colo/download` (33MB) はクローラに開かれている
- **分類**: 単なる変更 (なし) / **影響度**: 低
- **根拠**: public/robots.txt; `diff` 一致
- **確認方法**: curl 確認済み

### API-50 静的データファイル
- `/analysisList.tab`: 両方 200 (2018 年版と 2026-02 版、同サイズ 32228 B)。`/tables/lineNum.tsv`: 両方 200 (新は `text/tab-separated-values`)。`/tables/exp2run.json`: 旧 200 (34MB, 2018 年版) → 新 404。`/diff-analysis.examples.json`, `/examples/<genome>/{bedA,bedB,countA,geneA,geneB,motifA,motifB}.txt`: 両方 (新は hg19/mm9/dm3/ce10 のディレクトリも残置)
- **分類**: 機能削除 (exp2run.json) / 単なる変更 / **影響度**: 低
- **根拠**: `SCR/api/prod/{analysisList,lineNum,exp2run,diff_examples}.h`; `SCR/api/local/static_*.h`; `find public -type f`
- **確認方法**: curl 確認済み
- **備考**: `analysisList.tab` は新版では DB ロードの入力であって API ではないが、旧と同様に配信されている (旧 lib/pj/metadata.rb:22-33 のダウンロード先の名残)。

### API-51 POST の Content-Type 要件
- **旧**: `request.body` を Content-Type に関わらず `JSON.parse` (`/browse`, `/download`, `/colo`, `/target_genes`, `/diff_analysis_estimated_time`)。`/wabi_chipatlas` は JSON と form の両対応。不正 JSON は 500
- **新**: `JsonBodyParser` は `Content-Type` に `application/json` を含む POST だけ解析。form-urlencoded → 400 `{"error":"No JSON body"}`、壊れた JSON → 400 `{"error":"Invalid JSON"}`、空 body → 400 `{"error":"No JSON body"}`
- **分類**: 単なる変更 / **影響度**: 中 (`curl -d` の既定 Content-Type は form なので、ヘッダを付け忘れると全 POST が 400)
- **根拠**: old-app/app.rb:243-258, 477-487; lib/middleware/json_body_parser.rb:17-29, app.rb:49-54; `SCR/api/local/post_download_url_form.b`, `post_download_url_badjson.b`, `post_download_url_nobody.b`
- **確認方法**: curl+ソース確認済み

### API-52 サーバ側アクセスログの範囲
- **旧**: JSON body を持つ POST のみ `log/access_log` に `時刻 IP パス 本文` を記録 (app.rb:91-103)
- **新**: 同様の POST 記録に加え、`/api/search` の `q`・`genome`、`/api/colo`・`/api/target_genes` の条件、`/view` の id、ジョブ投入 (`job_submit`: type/backend/job_id)、`/enrichment_analysis` POST の taxonomy を IP 付きで日次ローテーション記録 (app.rb:56-68, routes/api.rb:99, 169, 210, routes/pages.rb:35, 95, routes/jobs.rb:58)
- **分類**: 単なる変更 / **影響度**: 低 (旧 README の「クエリを記録する」開示範囲内だが、GET の検索語まで対象が広がった)
- **根拠**: 上記行番号
- **確認方法**: ソース推定

### API-53 未検証パラメータで 500 になる経路 (新版)
- **新**: (a) `/api/target_genes?genome=a%20b&track=CTCF&distance=1` → 500 (`URI::InvalidURIError`; genome/track を検証せず URL に埋める。開発モードでは text/plain のバックトレース、本番モードでは HTML `Internal Server Error`)。同様に改行入りの値 (`CTCF.1\n.tsv`) もクラッシュログに記録あり。(b) `/api/igv_url` の Annotation tracks + 不明 subclass → 500 (`Bedfile::NotFound` 未捕捉; API-20)。(c) クラッシュ前のログには他エージェントのファジングによる `Sequel::DatabaseError: row value misused` (配列パラメータ)、`NoMethodError: upcase for Array` (`/view?id[]=`)、`TypeError` などの 500 も 12 件以上
- **旧**: 対応する経路は無いか、同様に 500 (`/view` id 無し、`/api/remoteUrlStatus` url 無し)
- **分類**: 退行 (要修正) / **影響度**: 低〜中 (JSON エラー契約 (API-38) の例外)
- **根拠**: ローカル curl (本節末尾の検証ログ); `SCR/api/container-crash-stderr.log` (14:15:47-14:16:00 の例外行); lib/services/location_service.rb:26, 43, data_proxy.rb:56
- **確認方法**: curl+ソース確認済み
- **備考**: `genome` は `ChipAtlas::Experiment.genomes.key?` で、`distance` は `TARGET_GENES_DISTANCES` で検証して 400 を返せば済む。

### API-54 ローカル新版プロセスのクラッシュ (SQLite `[BUG] Bus Error`)
- **事象**: 2026-09-23 14:16 UTC (JST 23:16) 頃、`chip-atlas-local` (ruby 4.0.5, puma 単一プロセス・10 スレッド, `-e development`, DB は bind mount 上の `database.sqlite.verify`) が `sqlite3/resultset.rb:43: [BUG] Bus Error at 0x0000ffffbe93d6c6` で異常終了 (exit 133)。制御フレームは `/app/lib/models/experiment_search.rb:117` (`/api/search` の genome 無し分岐、routes/api.rb:100) → Sequel → sqlite3 `step`。フォルトアドレスはプロセスマップ上 `rw-s ... /app/database.sqlite.verify-shm` (WAL の共有メモリファイルの mmap 領域) に含まれる。直前 30 秒間は複数エージェントの並行リクエスト (ファジング含む)。`docker start chip-atlas-local` で再起動し、約 1 分で `/health` 200 に復帰 (**監査中に環境操作を行った**)
- **分類**: 退行 (要修正) の可能性 / データ差分ではない
- **影響度**: 中 (再現性・本番環境での発生条件が不明)
- **根拠**: `SCR/api/container-crash-stderr.log` 1295 行目以降 (bug report, control frame, threading information "Ruby thread count 10", memory map); `docker inspect chip-atlas-local` (RACK_ENV=development, bind mount `/Users/inutano/repos/chip-atlas` → `/app`); lib/db.rb:9-12 (`journal_mode=WAL`, `mmap_size=256MB`)
- **確認方法**: ログ確認済み (原因は推定)
- **備考**: Docker Desktop の bind mount (virtiofs) 上で SQLite WAL の `-shm` を mmap すると SIGBUS が出る事例は知られており、ローカル環境固有の可能性が高い。ただし本番も puma マルチスレッド + WAL + `mmap_size=256MB` なので、`PRAGMA mmap_size` の妥当性と、`sqlite3` gem 2.9.1 + Ruby 4.0.5 の組み合わせでの負荷試験は本番前に必要。旧版 (unicorn 2 プロセス、スレッド無し、ActiveRecord) には同種の懸念はない。

### API-55 新規エンドポイント (`/api/stats`, `/api/target_genes_distances`)
- **新**: `/api/stats` → `{"total_experiments":454476,"total_experiments_formatted":"454,000","by_genome":{...},"by_track_class":{...}}` (旧はトップページの数字のみ)。`/api/target_genes_distances` → `[{"id":"1","label":"1 kb"},...]` (旧はハードコード)
- **分類**: 新機能 / **影響度**: 低
- **根拠**: routes/api.rb:53-56, 126-129; `SCR/api/local/stats.b`, `target_genes_distances.b`
- **確認方法**: curl+ソース確認済み
- **備考**: `by_track_class` に "No description" 25,689 件と "Unclassified" 38,245 件が現れ、`/api/track_classes` の 8 分類と一致しない (データ差分として UI 担当と共有)。

### API-56 性能特性の差 (API 利用者に見える範囲)
- **旧**: 分類・索引 API は起動時に計算した settings を返す (毎回 DB クエリなし、`index_all_genome` 等)。`/data/search` は毎回 COUNT + SELECT の 2 クエリ
- **新**: 分類 API は毎回 GROUP BY (SQLite)、`genome_index` は 1 時間キャッシュ、`/api/search` は `COUNT(*) OVER()` 1 クエリ、`/api/colo` は毎回 dbcls から TSV 取得・解析 (キャッシュ無し、263KB→407KB JSON)、`/api/target_genes` は 5 分キャッシュ、`/api/download_url`・`/api/igv_url` は外部 HEAD (最大 2 回 × 2 秒)、`/status` は外部 HEAD を 60 秒キャッシュ、`/api/colo/download` はファイル全体をメモリに載せてから返す
- **分類**: 単なる変更 / **影響度**: 低
- **根拠**: old-app/app.rb:70-83; lib/models/experiment.rb:107-116, lib/services/colo_tsv.rb:47-56, target_genes_tsv.rb:61-62, bed_extension_resolver.rb:31-32, service_monitor.rb:12, data_proxy.rb:63-66
- **確認方法**: ソース推定 (+ curl のサイズ実測)

---

### 検証ログ抜粋 (本文中で参照したもの)

```
# 本番 (chip-atlas.org)
/data/search?q=CTCF&genome=hg38&limit=3      -> 200 {"total":0,"returned":0,"experiments":[]}
/data/search?q=SRX018625&limit=2             -> 200 total 1, "genome":"hg19, hg38"
/data/search?q=SRX018625&genome=hg38&limit=2 -> 200 total 0
/data/chip_antigen?genome=hg38&agClass=Histone (clClass 無し) -> 200 [{"id":"-","label":"All","count":null}]
/colo_result?base=https://chip-atlas.dbcls.jp/data/hg38/colo/STAT3.Blood.html -> 500
/api/remoteUrlStatus?url=https://chip-atlas.dbcls.jp/data/hg38/colo/STAT3.Blood.tsv -> 200, content-length: 0
/diff_analysis_log?id=nonexistent -> 404 (HTML 6513 B)
Host: evil.example.com /health -> 403 "Host not permitted"
# ローカル (localhost:9292)
/api/track_subclasses?genome=hg38&track_class=Histone                          -> 200 39 B (All 行のみ)
/api/track_subclasses?genome=hg38&track_class=Histone&cell_type_class=undefined -> 200 6478 B
/api/target_genes?genome=a%20b&track=CTCF&distance=1 -> 500 URI::InvalidURIError
/api/igv_url?genome=hg38&track_class=Annotation%20tracks&track_subclass=NOPE&cell_type_class=All%20cell%20types&qval=05 -> 500 Bedfile::NotFound
/api/download_url (同条件) -> 200 {"url":null}
/api/target_genes?genome=dm6&track=E(z)&distance=5&limit=1 -> 200
/api/colo/download?genome=hg38&track=STAT3&cell_type=Blood&format=gml -> 200 33,228,517 B application/xml, filename="STAT3.Blood.gml"
旧 27 パス (/data/*, /qvalue_range, /browse, /download, /colo POST, /target_genes POST, /wabi_*, /*_log, /diff_analysis_estimated_time, /api/remoteUrlStatus, /.well-known/mcp.json, /style.css) -> すべて 404
# python 照合
hg38 colo: 旧 antigen 1767 / 新 track 1653、差 114 件はすべて旧で ["-"]; 旧 cellline["-"] = 114 件
target_genes_index hg38/mm10: 旧新の名前集合一致 (差 0)
特殊文字を含む track 名: 全ゲノムで 0 件 (括弧付きは dm6 のみ 15 件)
分類 API の順序: sample_types/chip_antigen (旧) と cell_type_classes/track_subclasses (新) は同順・同件数
```

---

## 要ブラウザ確認リスト
1. 旧形式 URL `/enrichment_analysis_result?id=X&api=wabi&title=..` を新版で開いたときのエラー表示内容 (API-36)。
2. `/agents` ページのコードブロック (コピー UI `_copy_code`) と表の描画崩れの有無 (API-48)。
3. `/api/igv_url` が返す `http://localhost:60151/load?...` を実際の IGV で開けるか (旧と同一 URL なので差は無い想定)。

## 未確認・不確実事項
1. 旧版の POST 系 (`/browse`, `/download`, `/colo`, `/target_genes`, `/wabi_chipatlas`, `/diff_analysis_estimated_time`) と GET `/wabi_chipatlas?id=` は本番に対して実行していない (BRIEF の制約)。応答形状・文字列は old-app/app.rb からの推定。
2. 新 `/jobs/submit` の成功応答 `{backend, job_id}` は routes/jobs.rb:59 / compute_router.rb:59 からの推定 (実ジョブは投入していない)。502 (`submission_rejected`) も未再現。
3. 本番の nginx 設定 (proxy cache の `x-cache`、`/data/ExperimentList.json` の静的配信) はレスポンスヘッダからの推定で、リポジトリ内の old-app/config/nginx/chip-atlas.conf とは一致しない。新版デプロイ時の nginx 設定 (config/nginx/chip-atlas.conf) に proxy cache が無いことは確認したが、実機に何が置かれるかは不明。
4. レート制限の有無: 旧新ともコード・リポジトリ内 nginx 設定に無し。本番 nginx / 上流 (CDN, WAF) に存在するかは未検証 (今回の軽量アクセスでは 429 等は観測されず)。
5. 新版本番イメージで `/ExperimentList.json` `/ExperimentList_adv.json` が 404 になるかは `.dockerignore` からの推定。デプロイ手順 (script/, .github/workflows) がファイルを別途配置する可能性は未確認。
6. 旧版本番で diff_analysis のジョブ投入が実際に成功するか (WABI 側が受け付けるか) は未検証。新版で常に 503 になる事実のみ確認。
7. ローカル新版のクラッシュ (API-54) の再現性と原因 (bind mount 上の WAL shm の mmap か、sqlite3 gem/Ruby 4.0.5 のスレッド安全性か) は未特定。私が `docker start chip-atlas-local` で再起動した (他エージェントのリクエストと並行していたため、トリガーとなったリクエストは特定できない)。
8. `/api/remote_url_status` の例外経路 (本文 "500") と `/api/colo` の 502 (ParseError) は未再現。
9. 新 openapi.yaml の照合はパラメータ名・応答形状レベルで 26 paths を目視し、13 点を実測で確認した。JSON Schema バリデータによる機械照合はしていない。
10. 旧 `/data/ExperimentList_adv.json` をアプリ (Sinatra) 経由で取得した場合の挙動 (nginx にファイルが無い場合の `JSON.dump` 170MB) は本番で試していない。
