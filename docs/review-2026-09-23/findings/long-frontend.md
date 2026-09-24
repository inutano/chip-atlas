# LONG-FE: フロントエンド / テンプレート / ビルド観点の 10 年メンテナンスフリー評価

- 対象: `/Users/inutano/repos/chip-atlas` (sengu ブランチ、HEAD 71cc650、2026-09-23 時点の作業ツリー)
- 範囲: `frontend/**/*.ts`, `esbuild.config.mjs`, `package.json`/`package-lock.json`, `frontend/tsconfig*.json`, `script/dev/*.sh`, `views/*.erb`, `views/*.markdown`, `public/css/*`, `public/js/bootstrap.bundle.min.js`, `public/icons/`, `public/examples/`, `public/*.json|yaml|txt|tab`, `public/tables/`
- 方法: 全ファイル読解、`git`/`grep`/`stat` による確認、ローカル (http://localhost:9292) への軽量 GET/HEAD、外部リンクへの HEAD 各 1 回、`script/dev/test-frontend.sh` と `tsc --noEmit` の実行 (いずれも読み取りのみ、リポジトリは無変更)
- 前提 (FORMAT-LONG.md): 外部サービス・レジストリ・Bootstrap は不変と仮定

## 担当範囲の要約と総評

1. ランタイムの外部依存は最小で良好。配信される CSS/JS/アイコンはすべて同梱 (Bootstrap 5.3.3 CSS + bundle (Popper 同梱確認)、`style.css` 688 行、SVG スプライト 1 枚)。CDN・外部フォント・外部スクリプトの読み込みはゼロ (`views/*.erb`・`style.css`・`frontend/**/*.ts` の `https?://` を全列挙して確認)。使用ブラウザ API は ES2020 + 標準 DOM のみで、10 年先のブラウザで壊れる要素は見当たらない。
2. 最大の弱点はビルドとデプロイの断絶 (LONG-FE-01)。`public/js/*.js` は `.gitignore` され、Dockerfile・deploy.sh・CI のどこにも「ビルドして本番に届ける」工程がない。クリーンな環境から出すと HTML は 200 のまま全ページの JS が 404 になり、`/health` は green のまま。2031 年の保守者が「テンプレート 1 行修正」で最初に踏む罠であり、手順書もない。
3. 「動いているように見えて壊れている」系が複数: ジョブ結果ページはバックエンド 503 や `unknown` を永久に "Requesting" のまま 10 秒間隔でポーリングし続ける (LONG-FE-02)。Peak Browser / Enrichment / Colo / Target Genes のファセット読み込み失敗は画面に何も出ない (LONG-FE-06)。
4. エージェント向けドキュメント (agents / demo / llms.txt / openapi.yaml) はルート実装と既に乖離している (TAIR10 vs TAIR12、"1M experiments"、`/status` の形、colo の例、`type` パラメータ) (LONG-FE-04)。
5. `public/` に 205 MB の stale データ (`ExperimentList*.json`) と旧ゲノムの表・例データが残り、そのまま配信される。`.gitignore` の大文字小文字問題で本番 (Linux) ではコミット事故の芽にもなる (LONG-FE-03)。
6. 外部リンクは views 内 31 本中 1 本が既に 404 (Enrichment ページの "node status")、experiment ページの TogoVar ドメインは応答なし、ATCC/RIKEN の深いリンクは検索語を失う (LONG-FE-05)。
7. テスト (147 件) と型検査は green で、ランナーの false-green 対策も読解で確認済み (LONG-FE-18)。
8. 担当外だが、レビュー中に `/api/search` 起因の sqlite3 gem Bus Error でローカルアプリが落ちた (restart ポリシーなし)。`docker start` で復旧させた (LONG-FE-X1)。

集計: 高 1 (+担当外 1)、中 7、低 10。

---

### LONG-FE-01 コンパイル済み JS が git 管理外で、どのデプロイ経路にもビルド工程がない
- **リスク度**: 高
- **顕在化時期**: 初回デプロイ時 (クリーンなマシン/クローンから出した瞬間)、および将来の「1 行修正」のたび
- **場所**: `.gitignore:24-47`, `Dockerfile:3`, `.dockerignore:14-18`, `.github/workflows/ci.yml:48-56`, `script/deploy/deploy.sh:230-262`, `app.rb:38-42`, `views/layout.erb:18-21`, `package.json`, `esbuild.config.mjs:16-25`, `routes/health.rb:8-24`
- **内容**:
  - `git check-ignore -v public/js/homepage.js` → `.gitignore:25` で無視 (確認済み)。`git ls-files public/js` に載るのは `bootstrap.bundle.min.js` だけ。11 本のページバンドルは `npm run build` の産物で、ローカルの `public/js/*.js` は 2026-09-22 16:38 に非 minify + `.map` 付きでビルドされたもの (`NODE_ENV=production` 未指定の形、`esbuild.config.mjs:22-23`)。
  - 届ける経路が存在しない:
    - `Dockerfile:3` は `COPY . /app` のみ。`.dockerignore:16-18` が `frontend/` と `node_modules` を除外し、コメントで「TypeScript is precompiled to public/js (no Node in the runtime image)」と *ホストでビルド済み* を暗黙の前提にしている。`docker-compose.yml` もビルドしない。
    - `script/deploy/deploy.sh:230-262` (deploy.yml から呼ばれる唯一の本番手順) は `git reset --hard origin/master` → `bundle install` → `rake pj:load_metadata` → `unicorn -c unicorn.rb` で、`npm`/`node`/`esbuild` の文字がない (`grep -rn 'npm\|node \|esbuild' script/` 該当 0 件)。しかも `unicorn.rb` は存在せず `pj:` namespace も Rakefile にない = 旧アプリ用のまま。
    - CI (`ci.yml:48-56`) は `npm ci` → `tsc` → `npm run build` → frontend テストまで行うが、成果物を `upload-artifact` せず Docker image も作らない。ビルドは検証のみで公開されない。
    - README.md にフロントエンドの記述なし。`npm run build` が書かれているのは `docs/superpowers/plans/2026-09-14-ui-parity-with-production.md:22` のみ。
  - 欠けたときの症状 (ソースで確認): `asset_path` (`app.rb:38-42`) は `File.exist?` が偽なら `?v=` なしのパスを黙って返す → `<script type="module" src="/js/peak-browser.js">` (`layout.erb:20`) → nginx `try_files $uri @app` → Sinatra `not_found` が HTML の 404 ページを返す (`routes/pages.rb:152-164`) → ブラウザは "Expected a JavaScript module script but the server responded with a MIME type of text/html" をコンソールに出すだけ。ページは描画され、ゲノムタブ・リストボックス・ボタンは空で無反応。`/health` は DB の疎通と件数しか見ない。Ruby テストにバンドル存在の assert はない (`grep -rn 'type="module"\|/js/' test/` は旧フィクスチャ `test/enrichment_test.html:12` のみ)。
  - 2031 年の保守者が 1 行のテンプレート修正を出すのに必要な手順 (現状、どこにも書かれていない): (1) Node.js を用意 (版指定なし: `package.json` に `engines` なし、`.nvmrc` なし、CI も `ubuntu-latest` 既定) → (2) `npm ci` (`package-lock.json` v3; esbuild 0.21.5 本体と `@esbuild/<os>-<arch>` プラットフォームバイナリ (lock に 23 種、`package-lock.json:13-387`) を registry.npmjs.org から取得。オフライン/私設レジストリ/未収載アーキでは失敗) → (3) `NODE_ENV=production npm run build` → (4) その `public/js/` を含む状態で `docker build` するか、インスタンスに rsync する。`node_modules` を失うと (2) からやり直しで、レジストリ到達性が前提になる。
- **推奨対策**:
  1. 最も堅いのは成果物のコミット: `.gitignore:24-47` を削除し、minify 済みバンドル (合計 ~150 KB) を追跡。CI に `NODE_ENV=production npm run build && git diff --exit-code public/js` を入れて乖離を検出。10 年観点では「Ruby だけで動く」状態が価値。
  2. 代替: Dockerfile を multi-stage 化 (`FROM node:22-slim AS fe` で `npm ci && NODE_ENV=production npm run build`、`COPY --from=fe /app/public/js /app/public/js`) して image を自己完結にする。
  3. 起動時に `@page_js` で参照する 11 バンドルの存在を検査し、`/health` の `checks` に `frontend_bundles: ok|missing` を追加 (missing なら 503)。
  4. README にビルド/デプロイ手順、`package.json` に `engines.node`、`.nvmrc` を追加。`deploy.sh` は新アプリ (puma, `rake metadata:*`) に書き直すか削除。
- **確認状況**: `ソース/設定で確認済み` (欠落時のブラウザ挙動のみ推定)

### LONG-FE-02 ジョブ結果ページのポーリングが終端せず、503/unknown をユーザに見せない
- **リスク度**: 中
- **顕在化時期**: WABI (dtn1.ddbj.nig.ac.jp) の保守停止・障害時、および結果 URL を後日開き直したとき (ページ自身が「1 週間有効」と案内)
- **場所**: `frontend/components/job-tracker.ts:16-20, 201-225, 257-278, 305`, `frontend/api/client.ts:152-157, 212-219`, `routes/jobs.rb:78-91, 107-122`, `views/enrichment_analysis_result.erb:24,33`, `views/diff_analysis_result.erb:24,33`
- **内容**:
  - `POLL_INTERVAL_MS = 10_000` 固定、最大回数・バックオフ・総時間上限なし (`job-tracker.ts:16, 224, 275`)。status と log の 2 系統が独立に走り、タブを開いている限り 720 req/h をアプリへ送り、アプリはそれを WABI へ転送する (`lib/services/wabi_service.rb:106-116, 143-147`)。`document.hidden` でも止まらない。
  - `routes/jobs.rb:82-87` はバックエンド停止時に 503 と `{status:'backend_unavailable', retry:false}` を返すが、`client.ts:214-216` は非 2xx を `ApiError` として throw して本文を捨てる。`poll()` の catch (`job-tracker.ts:221-224`) は `console.warn` して再スケジュールするだけ。よって `FAILED_STATUSES` の `'backend_unavailable'` (`:20`) と `JobStatus.retry` (`client.ts:156`) には到達する経路がない。画面はステータス欄が ERB の初期値 "Requesting" (`erb:33`) のまま、ログ欄は "Log file not available yet. This page refreshes on its own." (`job-tracker.ts:265`) を出し続ける。
  - WABI が ID を知らない (ジョブ削除後、typo、WABI 側障害) 場合、`ComputeRouter.status` → nil → `'unknown'` (`routes/jobs.rb:90`) → FINISHED/FAILED いずれでもなく永久ポーリング。想定語彙は "finished"/"running" 系のみ (`wabi_service.rb:97-133`) で、それ以外の終端語が来ても同様。
  - 1 秒間隔の時計 (`:305`) も含め、タイマーはページ離脱まで解放されない。
- **推奨対策**: (1) `ApiError.body` を JSON として読み、`status` があれば表示 (503 → "Compute backend is unavailable"); (2) `'unknown'` が N 回連続したら終端扱いにして「ジョブが見つかりません (期限切れの可能性)」を表示; (3) 上限 (例: 推定時間×3 または 24 h) と 10 s → 60 s のバックオフ; (4) `visibilitychange` で非表示中は停止; (5) log の 404 を「まだ無い」と「もう無い」で区別。`poll()` を注入可能にして 503/unknown のユニットテストを追加。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-03 `public/` の 205 MB stale メタデータと旧ゲノム表がそのまま配信され、`.gitignore` は Linux で効かない
- **リスク度**: 中
- **顕在化時期**: 初回デプロイ時から (配信中)。コミット事故は本番/CI (Linux) で `git add -A` した瞬間
- **場所**: `public/ExperimentList.json` (44,110,965 B, 2026-03-10), `public/ExperimentList_adv.json` (170,745,570 B, 2026-09-13), `public/analysisList.tab` (32,228 B, git 管理, 2026-02-22), `public/tables/lineNum.tsv` (74,245 B, git 管理), `.gitignore:12`, `.dockerignore:10-11`, `lib/tasks/metadata.rake:20-27`
- **内容**:
  - 新アプリはこれらを読まない: `metadata.rake` は `metadata/<datetime>/` に取得して DB へロードし、`lib/`・`routes/` に `public/` 配下のデータ参照はない (grep 確認)。`analysisList.tab` と `lineNum.tsv` の `public/` 側コピーは `ce10`/`hg19` など廃止ゲノム行を含む 2026-02 の stale copy。
  - Sinatra の `public_folder` と nginx `location / { try_files $uri @app; }` により `GET /ExperimentList_adv.json` 等は 200 で配信される (ローカル確認: `/ExperimentList.json` 200 application/json、`/ExperimentList_adv.json` 200、`/analysisList.tab` 200、`/tables/lineNum.tsv` 200)。旧版利用者やクローラは 10 年間、更新されない 2026 年 3 月のメタデータを取得し続ける。
  - `.gitignore:12` の `experimentList*json` は小文字始まり。macOS では `core.ignorecase=true` のため一致し (`git check-ignore -v` で確認)、Linux の本番/CI では大文字 `ExperimentList.json` に一致しない (git の仕様からの推定) → 未追跡ファイルとして見え、`git add -A` で 205 MB がコミットされる。`.dockerignore:10-11` は明示パスで除外しているので Docker 経路のみ安全。
- **推奨対策**: `public/` から 4 ファイルを削除 (`git rm public/analysisList.tab public/tables/lineNum.tsv`、JSON 2 本は物理削除); `.gitignore` を `[Ee]xperimentList*json` に; nginx に `location ~* ^/(ExperimentList|analysisList|tables/) { return 410; }` を追加し、旧 URL には `/api/search` への案内を返す。
- **確認状況**: `ソース/設定で確認済み` + `ローカルで再現` (配信); Linux での ignore 不一致は `推定`

### LONG-FE-04 エージェント向けドキュメント (agents / demo / llms.txt / openapi) がルート実装と乖離
- **リスク度**: 中
- **顕在化時期**: 初回デプロイ時から。乖離は 10 年で広がる一方
- **場所**: `views/agents.markdown:16,26,41,74,89`, `views/demo.markdown:5,110`, `public/llms.txt:3,27,47-48,63,77,91`, `public/openapi.yaml:115-127,199-208,418,904-908,1207-1227,1333-1367`, `public/robots.txt:20-25`
- **内容** (ローカル API の実応答と `routes/*.rb` で照合):
  1. ゲノム "TAIR10" (`agents:26`, `demo:5`, `llms:27,63`, `openapi:126,418` の enum) — 実際は "TAIR12" (`/api/genomes` 確認)。エージェントが `genome=TAIR10` を送ると空/404。
  2. "over 1 million experiments" / "over 1M" (`demo:5`, `llms:3`) — 実際 454,476 (`/api/stats`; 本番 433,000)。
  3. `/status` の形: `llms:77` と `openapi:199-208, 1223-1227` は `data_server/wabi/wes` の boolean と `feature_status` を記述。実際は `{"services":{"data_server":"ok","wabi":"ok","wes":"not_checked"},"features":{...}}` (`routes/health.rb:27-40`、ローカル確認)。`.wabi === true` を見るエージェントは常に「停止中」と判断する。
  4. colo の例 `cell_type=K-562` (`agents:74`, `demo:110`, `llms:47-48`, `openapi:904-908`) — colo の `cell_type` は細胞型クラス。`/api/colo_index?genome=hg38` の CTCF は `['Adipocyte','Blood','Bone',...]` で K-562 を含まない (確認) → 404 "Colocalization data not found"。
  5. `/jobs/:id/result?backend=wabi` (`agents:89`, `llms:58,99`, `openapi:1333-1367`) — diff ジョブは `type=diff_analysis` が必須 (`routes/jobs.rb:27-33, 102`)。省略時は enrichment 扱いで zip キーが返らない。未記載。
  6. `agents:41` "Each returns an array of {id, label, count}" — genome なしの `/api/track_classes` は `count` キー自体が無い (確認)。
  7. `llms:91` "The search index is populated at app startup" — 実際は rake によるロード時 (`lib/tasks/metadata.rake`, `lib/models/experiment_search.rb:15-19`)。
  8. `robots.txt:20-25` は `/data` `/browse` `/download` `/wabi_chipatlas` という存在しないパスを Disallow (無害だが放置の印)。
- **推奨対策**: ドキュメント内の定数 (ゲノム一覧・件数) をテンプレートで `/api/genomes`・`/api/stats` から埋める; `openapi.yaml` の全 `example` を実ルートへ投げて 2xx を確認する Ruby テストを追加 (agents.markdown 内の `GET ...` 行も同様に抽出して検証); `/status` スキーマと `type` パラメータを修正。
- **確認状況**: `ソース/設定で確認済み` + `ローカルで再現`

### LONG-FE-05 外部リンクの陳腐化 — 既に 404 が 1 本、応答なし 1 本、検索語を失う深いリンク 2 本
- **リスク度**: 中
- **顕在化時期**: 既に (2026-09-23 HEAD 確認)。残りも数年で順次
- **場所**: `views/enrichment_analysis.erb:133`, `frontend/pages/experiment.ts:171-189`, `views/_footer.erb:6-58`, `views/_navbar.erb:54`, `views/*.erb` の tutorial ハッシュ, `views/peak_browser.erb:11,64`, `views/search.erb:10`, `views/experiment.erb:129`
- **内容** (views 内 31 URL + experiment.ts の 9 テンプレート URL を HEAD 各 1 回、`-L` で追跡):
  - **404**: `enrichment_analysis.erb:133` "node status (epyc.q)" → `https://sc.ddbj.nig.ac.jp/en/guides/software/GridEngine/`。同じ役割のリンクは `diff_analysis.erb:87` と両 result erb (`:45-46`) が `/en/operation/job_queue_status/` (200) を使っており、1 行の不一致。
  - **応答なし (000, 40 s)**: `experiment.ts:189` TogoVar `https://togovar.biosciencedbc.jp/?term=…`。後継 `https://togovar.org/?term=CTCF` は HEAD 403 (bot 拒否の可能性、要ブラウザ確認)。
  - **検索語消失**: `experiment.ts:182` ATCC `http://www.atcc.org/Search_Results.aspx?searchTerms=…` → `https://www.atcc.org/home` (トップへ); `:184` RIKEN BRC `http://www2.brc.riken.jp/lab/cell/list.cgi?skey=…` → `https://cellbank.brc.riken.jp/cell_bank/WebSearch/?list.cgi` (汎用ページ)。どちらも 200 だが用をなさない。`:178` PDBj は `https://pdbj.org/search/pdb?query=CTCF` へ検索語付きで転送 (生存)。
  - **http:// のまま**: pdbj, atcc, riken (experiment.ts), `doi.org/10.7875/togotv.*` ×4 と `software.broadinstitute.org` (erb)。現状すべて https へ 301。
  - **生存確認**: 機関ロゴ 6 本、CC-BY、GitHub issues/wiki、NIG 保守ブログ、PDF マニュアル 6 本 (`chip-atlas.dbcls.jp/data/manual/*`)、YouTube 4 本、統合 TV DOI 4 本、IGV (→ `igv.org/doc/desktop/`)、DDBJ/NCBI SRA/ENA/MeSH/GEO/wikigenes、データサーバの bw/bb/bed 各 1 本。wiki のアンカー (`#igv_doc`, `#2-primary-processing`, `#tables-summarizing-metadata-and-files`) は HEAD では検証不能。
  - `_footer.erb:58` は個人メール 2 件 (`okishinya@`, `zou@kumamoto-u.ac.jp`) への mailto。
- **推奨対策**: リンクを `config/links.yml` (または 1 モジュール) に集約し、CI の `schedule` (月次) で `curl -sIL` チェックして失敗を issue 化; GridEngine を `job_queue_status` に、TogoVar を `togovar.org` に更新; ATCC/RIKEN は現行の検索 URL に差し替えるか削除; 連絡先は役割メールに。
- **確認状況**: `ローカルで再現` (HEAD 結果) / TogoVar 新ドメインは `未確認`

### LONG-FE-06 ファセット/索引の読み込み失敗が画面に出ない (Peak Browser, Enrichment, Colo, Target Genes)
- **リスク度**: 中
- **顕在化時期**: API が 5xx を返す・DB が空・ネットワーク断のとき (数年のうちに必ず起きる障害時)
- **場所**: `frontend/components/facet-filter.ts:202-242, 320-348, 363-369`, `frontend/pages/peak-browser.ts:154-161`, `frontend/pages/enrichment-analysis.ts:702-712`, `frontend/pages/colo.ts:80-88`, `frontend/pages/target-genes.ts:36-40`
- **内容**: `initialLoad` は `listTrackClasses` → `listCellTypeClasses` → 2 つの subclass を順に await するが try/catch がない (`loadQvalRange` のみ catch)。呼び出し側の `genome-change` ハンドラは `await FacetFilter.init(...)` するだけで、失敗は unhandled rejection になる。画面: ゲノムタブは描画されるがリストボックスは空。"View on IGV" を押すと空条件で `/api/igv_url` に POST し "Failed to build IGV link." だけが出る。Colo (`colo.ts:85-86`) と Target Genes (`target-genes.ts:38-39`) は `console.warn` して空のオートコンプリートを出す。`views/peak_browser.erb:68` の `#action-status` や `#submit-status` は存在するのに初期化失敗時には使われない。ユーザは「データが無い」と「サーバが落ちている」を区別できず、運用者にも通知されない (同じ API を使う `/status` の `features` は使われていない: `serviceStatus()` は未使用 export、LONG-FE-16)。
- **推奨対策**: `FacetFilter.init`/`setGenome` を try/catch し、container に `facet-error` を dispatch → 各ページの status 要素に "Could not load track classes (HTTP 503). Reload, or check /status." を表示; ページ読み込み時に `/status` を 1 回見て `features.*==='unavailable'` ならバナー。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-07 `publications.markdown` (300 KB) を毎リクエスト kramdown でレンダリング、キャッシュなし
- **リスク度**: 中
- **顕在化時期**: クローラ/LLM スクレイパが `/publications` を連打したとき (数ヶ月〜数年; 頻度は増加傾向)
- **場所**: `views/publications.erb:8`, `views/publications.markdown` (300,918 B, 1,421 行, 最終更新 2026-02-22), `views/about.erb:119`, `views/agents.erb:8`, `views/demo.erb:8`, `config/puma.rb:14-18`, `config/nginx/chip-atlas.conf` (rate limit なし), `public/robots.txt:19`
- **内容**: 毎リクエスト `File.read` + `Kramdown::Document.new(..., input: 'GFM').to_html`。計測 (ローカル Docker, Apple Silicon): `curl -w %{time_total}` 3 回で **0.101 s / 0.119 s / 0.104 s**、応答 350,792 B。他ページは 5-20 ms (`/` 0.021 s, `/agents` 0.007 s, `/search` 0.005 s)。本番は 2 workers × 5 threads で Ruby の GVL があるため、実効 ~20 req/s で全 worker が塞がる。`/publications` は認証なしの GET で、`robots.txt` の `Crawl-delay: 30` は Google/Bing が無視する。`about.erb:119` も `updates.markdown` を毎回レンダリング (小さいので無視できる)。
- **推奨対策**: レンダリング結果をファイル mtime をキーにプロセス内メモ化 (数行); または `rake publications:build` で静的 HTML 化; nginx に `limit_req_zone` を追加。
- **確認状況**: `ローカルで再現`

### LONG-FE-08 IGV 到達性プローブがブラウザの Local Network Access 施策に依存する (推定)
- **リスク度**: 中 (推定)
- **顕在化時期**: ブラウザのポリシー変更時 (数ヶ月〜数年)
- **場所**: `frontend/components/igv.ts:20-42`, `frontend/pages/peak-browser.ts:170-184`, `frontend/pages/experiment.ts:275-291`
- **内容**: 新版は IGV へ遷移する前に `fetch('http://localhost:60151/echo', {mode:'no-cors', signal: 2 s})` で到達性を確かめ、失敗すると **遷移しない** (`peak-browser.ts:175-178`, `experiment.ts:284-286`)。旧版はリンクをそのまま開いていた (top-level navigation)。https の公開サイトから loopback への subresource fetch は Chrome の Private/Local Network Access 施策 (権限プロンプト化・既定ブロックへ段階移行中) の対象で、ユーザが許可しない・ブラウザが黙って拒否する場合、fetch は reject → "Could not reach IGV on localhost:60151. Start IGV…" (`igv.ts:22-24`) が IGV 稼働中でも出て、View on IGV が機能停止する。旧版にはなかった依存を新版が持ち込んだ形。2 秒タイムアウトは IGV 起動直後の重い状態で偽陰性になる。ポート 60151 自体は IGV の固定バッチポートで問題ない。
- **推奨対策**: プローブ失敗時も IGV URL を `<a href>` として表示し「IGV が起動済みならこちら」と手動遷移を残す (旧版と同じ経路を保持); プローブは補助表示に留める。
- **確認状況**: プローブの仕組みは `ソース/設定で確認済み`; ブラウザ側の挙動は `推定` (要ブラウザ確認)

### LONG-FE-09 TAIR12 の例データが無く、廃止ゲノムの例データ (~5 MB) が残る
- **リスク度**: 低
- **顕在化時期**: 初回デプロイ時から (TAIR12 タブで "Try with example")
- **場所**: `frontend/pages/enrichment-analysis.ts:635`, `public/examples/` (hg38 mm10 rn6 dm6 ce11 sacCer3 + 廃止 hg19 mm9 dm3 ce10; git 管理 70 ファイル, 11 MB), `frontend/pages/diff-analysis.ts:110-122`, `public/diff-analysis.examples.json` (キー hg/mm/rn/dm/ce/sacCer のみ)
- **内容**: `/examples/TAIR12/bedA.txt` は 404 (ローカル確認) → Enrichment は "Failed to load example data."。Diff は `genomeSpecies('TAIR12')='TAIR'` がキーに無く "No example data available for this genome and experiment type." (明示メッセージあり、graceful)。一方 `ce10/dm3/hg19/mm9` (1.4+0.46+1.1+2.0 MB) は配信され続ける死荷重。
- **推奨対策**: TAIR12 用の bedA/geneA 等を追加 (データ担当と調整); 廃止 4 ディレクトリを削除; `config/genomes.yml` の各ゲノムに例データが存在することをテストで検証。
- **確認状況**: `ローカルで再現`

### LONG-FE-10 ヘルプ文・ゲノム定数・「What's new」・助成番号・既定 ID の陳腐化
- **リスク度**: 低
- **顕在化時期**: 既に (ヘルプ文); データ再生成で新アセンブリを追加した時 (定数); 年単位 (What's new, 助成番号)
- **場所**: `frontend/pages/enrichment-analysis.ts:31-34, 331-343, 368-380, 433, 508-510`, `views/enrichment_analysis.erb:62,85`, `views/updates.markdown:4-8`, `views/about.erb:119`, `views/_footer.erb:43,58`, `views/_navbar.erb:66`
- **内容**:
  - `NOTE2` (`:33`) は info ボタン "genomic-regions"/"dataset-b-bed" で表示され「Acceptable genome assemblies: hg19, hg38 … mm9, mm10 … dm3, dm6 … ce10, ce11 … sacCer3」と廃止 4 アセンブリを列挙し TAIR12 が無い。`NOTE1` の命名規則にも A. thaliana が無い。
  - `GENOME_SIZE` / `NUM_GENES` はゲノム定数をコードにハードコード。新アセンブリを DB 側で追加しても推定時間は "—" になる (`motifLineCount:433`, `estimateSeconds:508-510`)。
  - `updates.markdown` の最新項目は 2024/05/16。ホーム (`about.erb:119`) に常時表示 → 2036 年には 12 年前の「What's new」。
  - `_footer.erb:43` 助成番号 JPMJND2202 (期限付き課題)、`:58` 個人メール。
  - `_navbar.erb:66` の既定 ID `SRX018625` はローカル DB に存在 (確認) するが、データ再生成で消えれば "Go" が 404。
- **推奨対策**: NOTE2 の一覧を `/api/genomes` から生成; 定数を `config/genomes.yml` に移し `page-data` に埋める; What's new は日付で自動的に畳む/削除; 連絡先は役割メール; 既定 ID は `/api/stats` 等から選ぶ。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-11 キャッシュバスティングは概ね正しいが、icons/logos が対象外で `.map` も配信される
- **リスク度**: 低
- **顕在化時期**: スプライト/ロゴ差し替え時 (数年)
- **場所**: `app.rb:35-42`, `views/layout.erb:9-10,18-20`, `views/_icon.erb:1`, `views/_footer.erb:7-32`, `config/nginx/chip-atlas.conf:26-42`, `esbuild.config.mjs:22-23`
- **内容** (分析):
  - `?v=<mtime>` は「そのマシンでファイルが書かれた時刻」であってコンテンツハッシュではない。git は mtime を保存しないため `clone`/`reset --hard` で *内容が変わったファイルだけ* mtime がその時刻になる (git の仕様からの推定) → 変更ファイルの URL は必ず変わり、未変更ファイルは据え置き = 正しい。
  - Docker `COPY` は mtime を保持する (**ローカルで再現**: 2020-01-01 の mtime を持つファイルを `COPY` したスクラッチ image 内で `stat` → 1577804400)。ビルドホストの mtime がそのまま本番に載るので、これも正しい。
  - blue-green の複数インスタンスで mtime が異なっても参照先は同内容なので無害。
  - 壊れるのは「内容を変えつつ mtime を保存する」操作だけ: `rsync -t` で古いアーカイブから復元、`touch -r`、`SOURCE_DATE_EPOCH` 付き reproducible build (全ファイル同一 mtime)。稀。
  - 対象外の資産: `/icons/chip-atlas.svg` (`_icon.erb:1`; nginx に location がなく `expires` なし → `Last-Modified` による heuristic cache) と `/images/logo/*` (`expires 7d`) は `?v=` を通らない → 差し替え後、最大 7 日 (logos) / 経過時間の 10% 程度 (icons) 古いものが出る。
  - `NODE_ENV` 未設定ビルドは非 minify + `.map` を配信 (ローカルで `/js/homepage.js.map` 200) — 害はないがソース公開。
  - HTML 自体は `Cache-Control`/`Last-Modified` なし → キャッシュされない (OK)。バンドルは esbuild で 1 ファイルに束ねられ `import` グラフはない (OK)。
- **推奨対策**: 起動時に一度計算した内容ハッシュ (SHA-256 先頭 8 桁) に置き換え、`_icon.erb` と footer 画像にも適用; 本番ビルドは `NODE_ENV=production` を CI/Dockerfile で強制。
- **確認状況**: `ソース/設定で確認済み` + `ローカルで再現` (Docker COPY); git の mtime 挙動は `推定`

### LONG-FE-12 fetch にタイムアウト/リトライがなく、結果ページのエラー文言が障害時に誤誘導する
- **リスク度**: 低
- **顕在化時期**: データサーバ (chip-atlas.dbcls.jp) の遅延・障害時
- **場所**: `frontend/api/client.ts:212-228`, `frontend/pages/colo-result.ts:562-573`, `frontend/pages/target-genes-result.ts:452-461`, `lib/services/data_proxy.rb:61-62`, `lib/services/wabi_service.rb:110-111,143-144`, `config/nginx/chip-atlas.conf:74-76`
- **内容**: `request()`/`requestText()` にタイムアウト/リトライなし (`AbortController` は `igv.ts` の 2 秒のみ)。サーバ側上限が data_proxy 10 s/30 s、WABI 5 s/10 s、nginx `proxy_read_timeout 120s` なので、最悪 ~30-120 秒 "Loading…" が出続けたのちエラー。開発 (nginx なし) では上限なし。colo/target 結果ページのエラー文言は "…may not have precomputed data." 固定で、502/503 (データサーバ障害) でも同文言 → ユーザは「そのデータは無い」と誤解する。`ApiError.status` を持っているのに使っていない。一方 `search.ts:188` は "Search failed. Please try again."、`homepage.ts:15-18` はサーバ描画値を維持 (良い)。
- **推奨対策**: `request()` に `AbortSignal.timeout(30_000)`; 結果ページは status 別文言 (404 → 未計算、5xx → データサーバ障害・後で再試行)。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-13 旧サイトの結果 URL が新版では全てエラー表示になる (移行時のみ) / robots.txt の死パス
- **リスク度**: 低
- **顕在化時期**: 初回デプロイ時 (切替前 1 週間分の結果リンクが対象。1 週間で自然消滅)
- **場所**: `frontend/components/result-page-params.ts:32-43`, `frontend/pages/enrichment-result.ts:11-20`, `frontend/pages/diff-result.ts:11-20`, `frontend/pages/colo-result.ts:52-59, 585-592`, `frontend/pages/target-genes-result.ts:48-55, 522-530`; 旧: `old-app/public/js/pj/enrichment_analysis.js:730-738`, `old-app/public/js/pj/diff_analysis.js:182-190`, `old-app/app.rb:288-289, 316-317`
- **内容**: 旧版の結果 URL は `?id=…&api=wabi&title=…&calcm=…` (diff は `?id=&title=&genome=&calcm=`)。新版は `backend` が必須で `api` を読まない → "Missing id or backend parameter in URL." を表示して停止。旧 `/colo_result?base=…`・`/target_genes_result?base=…` も "Missing genome, track, or cell_type parameter in URL."。ローカルで旧形式 URL を GET すると 200 の HTML シェル (エラーはクライアント描画)。旧 `?agClass=` 等は `/data/*` API 側の話 (別担当)。`robots.txt:20-25` は旧ルートを Disallow したまま (無害)。
- **推奨対策**: `readResultPageParams` で `api` を `backend` の別名として受理 (2 行); `base=` は旧 URL から genome/track を抽出できるなら変換、無理なら 410 + 案内文。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-14 `favicon.ico` が存在せず、nginx に死んだ `/webfonts/` location が残る
- **リスク度**: 低
- **顕在化時期**: 初回デプロイ時から (全訪問で 404 が 1 件ずつログに積まれる)
- **場所**: `views/layout.erb:3-11` (`<link rel="icon">` なし), `public/` (favicon.ico なし; `public/icons/chip-atlas.svg` はある), `config/nginx/chip-atlas.conf:44-53`
- **内容**: ブラウザは既定で `/favicon.ico` を要求する。nginx は `try_files $uri =404` で 404、開発では Sinatra `not_found` が HTML 404 ページをレンダリング (ローカル確認 404)。10 年分のログノイズと、タブにアイコンが出ない。`/webfonts/` は FontAwesome 廃止後に存在しないディレクトリ。
- **推奨対策**: `<link rel="icon" href="/icons/…">` と `favicon.ico` を追加; `/webfonts/` location を削除。
- **確認状況**: `ローカルで再現`

### LONG-FE-15 ツールチェーンの版固定が不完全 (Node 版指定なし、esbuild バイナリはレジストリ依存)
- **リスク度**: 低 (前提: レジストリ不変)
- **顕在化時期**: 新しいビルドマシン/CI ランナーに移ったとき (数年)
- **場所**: `package.json` (`engines` なし), `.nvmrc`/`.node-version` なし, `package-lock.json:404-406, 414-416, 453-455`, `.github/workflows/ci.yml:48-53` (Node 版指定なし), `esbuild.config.mjs`
- **内容**: lock は esbuild 0.21.5 (2024-06、0.21 系最終)、typescript 5.9.3、@types/node 26.6.1 に固定 (`npm ci` なら決定的)。esbuild は `@esbuild/<os>-<arch>` (lock に 23 種) を optionalDependencies として取得するため、オフライン・私設レジストリ・未収載アーキでは `npm ci` が失敗。ローカルは node v26.0.0 / npm 11.12.1、CI は `ubuntu-latest` 既定の Node。Node 26 は 2029 年頃 EOL (推定); esbuild 0.21 の JS ラッパは古い Node API しか使わないので将来の Node でも動く見込みだが保証はない。`npm install` (ci ではなく) を打っても `^0.21.0`/`^5.4.0` の範囲で現在は同じ版に解決する。
- **推奨対策**: `engines.node` + `.nvmrc` + CI で `actions/setup-node` の版固定; LONG-FE-01 の成果物コミットで Node をデプロイ経路から外す。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-16 死んだコード・設定、ページ間の重複ヘルパー、型ドリフト
- **リスク度**: 低
- **顕在化時期**: 将来の修正時 (2 箇所直し忘れ、使った瞬間に壊れる型)
- **場所**: `public/css/style.css:82-84, 281-283`, `frontend/tsconfig.json:15-18`, `frontend/api/client.ts:256, 291, 295, 330, 364, 391, 456, 460`, `frontend/pages/colo-result.ts` ↔ `frontend/pages/target-genes-result.ts`, `public/images/logo/`, `public/icons/chip-atlas.svg`, `test/enrichment_test.html:12`
- **内容**:
  - `style.css:82-84` `.navbar .nav-link i` — `<i>` 要素はもう無い (アイコンは `<svg class="icon">`、本物のルールは `:303-304`)。`:281-283` `.autocomplete-paired-list` は参照ゼロ (`autocomplete.ts` は ListBox を直接マウント)。
  - `tsconfig.json:15-18` の `paths` (`@api/*`, `@components/*`) は使用ゼロで、esbuild 側に alias 設定もない → 使うと `tsc` は通りビルドで壊れる罠。
  - `client.ts` の未使用 export 8 件: `listAllTrackClasses`, `getGenomeIndex`, `getExperiment`, `getTargetGenesDistances`, `downloadColoFile`, `downloadTargetGenesFile`, `healthCheck`, `serviceStatus`; 未使用 interface 14 件。うち `getTargetGenesDistances(): Promise<string[]>` は実 API `[{"id":"1","label":"1 kb"},…]` と不一致 (**型ドリフト**; 使った瞬間に壊れる)。`ServiceStatus`/`ExperimentRecord`/`SearchExperiment`/`Stats`/`JobAvailability`/`ColoIndex`/`TargetGenesIndex` は実応答と一致 (確認)。
  - 「6 個のバイト同一ヘルパー」(`docs/superpowers/plans/2026-09-18-post-parity-fixes-outcome.md:139`) = colo-result.ts ↔ target-genes-result.ts の `scoreToRgb` (174↔74), `rgbToHex` (191↔92), `readableTextColor` (195↔96), `formatScore` (272↔101), `computeNextSort` (286↔146), `computeAriaSort` (293↔156)。加えて `COLOR_STOPS` (166↔66), `splitExperimentHeader` (78↔121), `stringColumnIndex` (68↔112), `sortArrowGlyph` (324↔172), `sortStateHint` (329↔177), `makeSortableHeader` (345↔197), `wireExperimentsToggle` (576↔513) も同一で、`averageColumnIndex` (63↔107) だけフォールバック値が 3 と 1 で異なる。`$()` は 7 ページ、`readPageData()` は 5 ページで重複。`colo-result.ts:14-19` は「entry ごとに独立バンドルだから」と理由づけるが、`document.addEventListener` を持つページモジュールではなく純粋な共有モジュールを import すれば esbuild は必要な関数だけ束ねるので、理由は成立しない。修正は常に 2 箇所同時が必要。
  - `public/images/logo/ku_logo.jpg`, `kyoto_uni_logo.png` 参照ゼロ; スプライトの `robot`/`spinner`/`info-circle` 未使用 (使用 25 名はすべて定義あり)。
  - `test/enrichment_test.html:12` は jsdelivr の Bootstrap 3.4.1 を参照する旧フィクスチャ (配信されない; `.dockerignore` で除外)。
  - `TODO/FIXME/XXX/HACK`: `frontend/`, `views/`, `public/css` に 0 件。
- **推奨対策**: 共有ヘルパーを `frontend/components/matrix-table.ts` に移して両ページから import; 未使用 export/型/`paths`/CSS/画像を削除; `getTargetGenesDistances` の型を `ClassificationItem[]` 相当に。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-17 クリップボードの非推奨フォールバックと `alert()` の残存
- **リスク度**: 低
- **顕在化時期**: http で配信されたとき (開発・プロキシ設定ミス) / `execCommand` がブラウザから削除されたとき (数年)
- **場所**: `frontend/pages/search.ts:204-231`, `views/_copy_code.erb:3-31`, `frontend/pages/colo.ts:167,173,179`, `frontend/pages/target-genes.ts:61,70`
- **内容**: `navigator.clipboard` は secure context のみ。それ以外は `document.execCommand('copy')` (非推奨) にフォールバックし、戻り値を見ずに "Copied!" を表示する (`search.ts:222-227`, `_copy_code.erb:28-31`) → 失敗しても成功表示。本番 https では問題なし。Colo/Target Genes の未選択時は `alert()` (ブロッキング; `info-popover.ts:5-9` が自ら避けた理由と矛盾)。
- **推奨対策**: `execCommand` の戻り値で分岐; `alert` を status 要素の文言に。
- **確認状況**: `ソース/設定で確認済み`

### LONG-FE-18 テストランナーは false-green 対策済みだが bash 4+ 依存、DOM 配線は無テスト
- **リスク度**: 低
- **顕在化時期**: macOS 標準 bash だけの環境で実行したとき (loud に失敗、緑にはならない)
- **場所**: `script/dev/test-frontend.sh:17-56`, `frontend/tsconfig.test.json`, `frontend/**/*.test.ts` (9 ファイル), `script/dev/ui-parity.sh:14-15`, `script/dev/ui-checklist.sh:11`, `.github/workflows/ci.yml:55-56`
- **内容**:
  - ランナー読解: ソース数 (`find`) とコンパイル済み `.js` 数の一致検査 (`:47-54`) と空配列検査があり、"green while running nothing" 欠陥は防いでいる。`set -euo pipefail` により esbuild 失敗も loud。実行結果: **147 tests pass / 0 fail**、`tsc --noEmit` は app/test とも OK (ローカル、2026-09-23)。
  - `:38` `mapfile` は bash ≥ 4。macOS 標準 `/bin/bash` は 3.2.57 (確認) で "command not found" → `set -e` で非ゼロ終了 (false green ではない)。`#!/usr/bin/env bash` が Homebrew bash 5.3 を拾う環境依存。
  - テストがあるのは 22 ソース中 9: components は facet-filter, job-tracker (+result-page-params); pages は colo, colo-result, diff-analysis, enrichment-analysis, peak-browser, search, target-genes-result。autocomplete / list-box / genome-tabs / igv / info-popover / experiment / homepage / target-genes / enrichment-result / diff-result と全ページの `init()` (DOM 配線) は無テスト。LONG-FE-02 の「503 を捨てる」挙動はテストの死角。
  - `ui-parity.sh` は `chromium` と `magick` (ImageMagick 7) を要求し、`ui-checklist.sh:11` は `~/run/chip-atlas-local.sh` というユーザ固有パスをメッセージに含む (開発補助なので影響は小)。
- **推奨対策**: `poll()` を注入可能にして 503/unknown/upper-bound のテストを追加; README に bash 4+ を明記 (または `mapfile` を `while read` に)。
- **確認状況**: `ローカルで再現` (テスト実行) + `ソース/設定で確認済み`

### LONG-FE-X1 (担当外・観測) `/api/search` で sqlite3 gem が Bus Error を起こしプロセスごと落ちた — restart ポリシーなし
- **リスク度**: 高 (担当外: 検索/DB/運用担当へ引き継ぎ)
- **顕在化時期**: 特定条件 (特定の検索クエリ)
- **場所**: `docker logs chip-atlas-local` 1330-1353 行目, `lib/models/experiment_search.rb:117`, `routes/api.rb:100`, `~/run/chip-atlas-local.sh` (`WEB_CONCURRENCY=0`, `restart` 指定なし)
- **内容**: 2026-09-23 14:2x UTC、ローカルコンテナが `Exited (133)`。ログ: `sqlite3-2.9.1-aarch64-linux-gnu/lib/sqlite3/resultset.rb:43: [BUG] Bus Error at 0x0000ffffbe93d6c6` (ruby 4.0.5)、Control frame は `sequel-5.103.0/adapters/sqlite.rb:428` … `/app/lib/models/experiment_search.rb:117` ← `/app/routes/api.rb:100` (GET `/api/search`) ← puma 7.2.0。直前のログには別エージェントの `/api/search` リクエスト (`search {"q":null}` ×2、および QUERY_STRING 20,000 文字超の `HTTP parse error`) があり、私のリクエスト (GET `/api/colo_index`) とは無関係と推定。含意: 特定の FTS5 クエリで SQLite ネイティブ層がクラッシュし Ruby VM ごと落ちる。本番 (`config/puma.rb` の cluster 2 workers) では worker 再フォークで自己回復するが (推定)、単一プロセス・`restart` なし構成では手動復旧が必要。私は `docker start chip-atlas-local` で復旧させ `/health` 200 を確認した (コンテナの元コマンド `bundle install; puma` をそのまま再実行しただけ)。
- **推奨対策**: `log/access_log` 14:21:00 付近から再現クエリを特定; FTS5 クエリ文字列のサニタイズ/長さ制限 (puma の 10 KB 制限より手前で 400 に); sqlite3 gem/SQLite の版を確認; コンテナ/サービスに `restart: unless-stopped` 相当を設定; `/health` を外部監視に。
- **確認状況**: `ローカルで再現` (ログ) / 原因クエリは `未確認`

---

## 問題なしと確認した項目

- **外部資産の実行時読み込みはゼロ**: `views/*.erb`・`public/css/style.css`・`frontend/**/*.ts` の `https?://` を全列挙。CSS/JS/フォント/画像はすべて同一オリジン (`/css/bootstrap5.min.css`, `/css/style.css`, `/js/bootstrap.bundle.min.js`, `/icons/chip-atlas.svg`, `/images/logo/*`)。外部 URL はリンク先のみ。例外は `/view` の Comparative Profile 画像 (`experiment.erb:170-174` → `experiment.ts:224-247` が `chip-atlas.dbcls.jp` の PNG を `img.src` に設定) とダウンロード/IGV リンクで、いずれも前提により不変とみなすデータサーバ。
- **Bootstrap 5.3.3** で CSS と bundle の版が一致 (ヘッダで確認)。bundle に Popper 同梱 (`createPopper` 等を grep で確認)。使用機能は `collapse` (navbar) / `dropdown` (tutorial, `/view` の 4 メニュー) / `Popover` (`info-popover.ts`) のみで、すべて bundle 内。`window.bootstrap` 不在時は `initInfoPopovers` が黙って戻る (`info-popover.ts:29-30`)。
- **ブラウザ API**: `target: ['es2020']` + `type="module"` (nomodule フォールバックなし = 2017 年以前のブラウザには静的 HTML のみ; 10 年先方向には無関係)。使用: `fetch`, `URLSearchParams`, `AbortController` (igv.ts のみ), `Promise.allSettled`, `Element.replaceChildren`, `history.replaceState`, `CustomEvent`, `WeakMap`, `FileReader`, `Blob`/`URL.createObjectURL`, `<details>/<summary>`, `navigator.clipboard`。未使用 (grep 確認): `structuredClone`, `Array.prototype.at`, `Object.hasOwn`, `crypto.randomUUID`, `<dialog>`, `popover` 属性, `:has()`, `localStorage`/`sessionStorage` (→ スキーマ版管理の問題なし), `IntersectionObserver`/`ResizeObserver`。CSS のモダン機能は `gap`, `:focus-visible`, `overflow-wrap: anywhere`, `contain: layout paint`, `::marker`, `font-variant-numeric` で、いずれも 2021 年以降の全主要ブラウザで安定。
- **IGV のポート** `localhost:60151` は IGV の固定バッチポート (`igv.ts:20`, `experiment.ts:14`)。ハードコードで問題なし (プローブ手法は LONG-FE-08)。
- **`result-page-params.ts`** は `id`/`backend` 欠如を null で返し、両結果ページが可視エラーを出す (`enrichment-result.ts:12-20`)。`colo-result.ts:585-592`, `target-genes-result.ts:522-530` も同様に可視エラー。
- **日付/年のリテラル**: コード経路には無い。`job-tracker.ts:38-61` は `Date` の各フィールドから動的に整形し、`toString()` 依存を避けている (良い)。`©`/`as of` の類は views に無い。年が出るのは `updates.markdown` の履歴のみ (LONG-FE-10)。
- **SVG スプライト**: views で使う 25 個の `name:` はすべて `chip-atlas.svg` に `<symbol id>` がある (comm で確認)。
- **既定 ID `SRX018625`** はローカル DB に存在し `/api/experiment` が返す。
- **`.dockerignore`** は 205 MB の JSON を除外している (Docker 経路の image 肥大は起きない)。
- **テスト/型検査**: 147/147 pass、`tsc --noEmit` 2 プロジェクト OK、ランナーは false-green 対策済み (LONG-FE-18)。
- **HTML のキャッシュ**: `Cache-Control`/`Last-Modified` なしでブラウザにキャッシュされない。`?v=` の仕組み自体は変更ファイルを確実に無効化する (LONG-FE-11)。
- **TODO/FIXME/XXX**: 担当範囲に 0 件。
- **`views/_navbar.erb:63`** の inline `onsubmit` は `window.open` をユーザ操作内で呼ぶためポップアップブロックの対象外。CSP は未設定 (設定する日には inline handler と `_copy_code.erb` の inline script が要対応)。

## 未確認・不確実事項

- **要ブラウザ確認**: (a) Chrome/Safari/Firefox の Local Network Access 施策下で `igv.ts` の `no-cors` fetch がどう扱われるか (LONG-FE-08); (b) バンドル欠落時のコンソールエラー文言と画面 (LONG-FE-01 は挙動をソースから推定); (c) 旧形式 URL でのエラー表示 (LONG-FE-13; curl では HTML シェルのみ); (d) Bootstrap popover の実描画; (e) `contain: layout paint` の実機挙動 (`style.css:636-662` のコメントは本人検証済みと主張)。
- **TogoVar** の新ドメイン `togovar.org` は HEAD 403 (bot 拒否の可能性) で生死を断定できない。wiki のアンカー 3 件 (`#igv_doc` 等) は HEAD では検証不能。
- **本番のデプロイ経路**: `deploy.sh` は旧アプリ用で、sengu を実際にどう配備するか (Docker image をどこで build するか、`public/js` を誰が作るか) はリポジトリ内に記録がない。本番インスタンスに `public/ExperimentList*.json` が存在するか (存在すれば nginx が配信) も未確認。
- **git の mtime 挙動** (checkout で内容変更ファイルのみ mtime 更新) と **Linux での `.gitignore` 大文字小文字不一致** は git の仕様に基づく推定で、Linux 実機では試していない。`SOURCE_DATE_EPOCH`/buildx の reproducible モードでの `COPY` mtime も未試験。
- **CI ランナーの Node 版** (`ubuntu-latest` 既定) は未確認。
- **LONG-FE-X1 の再現クエリ** は特定していない (別担当の範囲; `log/access_log` 14:21:00 付近が手掛かり)。本番 puma cluster での自己回復も推定。
- **`/publications` の本番実測** はしていない (ローカル Apple Silicon の 0.10 s は本番 EC2 より速い可能性が高い)。
- **agents.markdown / demo.markdown の他の例** (Pluripotent stem cell, HNF4A/Liver, H3K4me3/Blood の `download_url`) はローカルで URL 生成まで確認 (`{"url":"https://chip-atlas.dbcls.jp/data/.../His.PSC.05.H3K4me3.AllCell.bed"}` 等) したが、データサーバ上にファイルが実在するかは確認していない (LocationService は存在確認をしない)。
