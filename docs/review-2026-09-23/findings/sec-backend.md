# ChIP-Atlas 新版 バックエンド セキュリティ監査 (担当接頭辞: SEC-BE)

対象: `/Users/inutano/repos/chip-atlas` (sengu ブランチ) の Ruby バックエンド
検証環境: ローカル docker `chip-atlas-local` (RACK_ENV=development, DB=database.sqlite.verify, http://localhost:9292)
本番前提: Ruby 4.0.5 / Puma 7 (単一/2worker×5thread) / nginx / AWS ALB / SQLite / 認証なし

## 担当範囲の要約と総評

- 認証・セッション・Cookie は一切なく、全エンドポイントが無認証。攻撃者が「盗む」対象 (資格情報・トークン) は存在しないため、CSRF/XSS よりも **SSRF・DoS・可用性** が実害の中心。
- SQL は全て Sequel のプレースホルダ経由でパラメタライズされており、**SQL インジェクションは検出されなかった**。FTS5 の MATCH 文字列も `fts5_sanitize` が二重引用符・演算子記号を除去してフレーズ化しており、FTS5 構文インジェクションも成立しない (多数のペイロードで実証、いずれも 500/構文破壊なし)。
- 最重要は 2 件。(1) `DataProxy` がユーザ制御の `genome/track/cell_type` から URL を組み立て、ホスト検査が「同一ホストなら通す」ため、`#`/`?`/`..` を使って **chip-atlas.dbcls.jp 上の任意パスを取得できるオープンプロキシ** になっている (実証済)。応答本文を全量メモリに読むため、同ホストが配信する 182GB の .bed を指すと **メモリ枯渇で落とせる**。(2) `/api/search` の `q` に長さ制限がなく、多トークンクエリが 1 リクエストで 37〜60 秒かかり、スレッドプール枯渇で **無認証 DoS** が成立する (監査中に実際にインスタンスが停止した)。
- 型混同 (配列/数値/ハッシュのパラメータ・JSON ボディ) で未処理例外 500 が多発する。**本番はスタックトレースを出さない** (`<h1>Internal Server Error</h1>` のみ、実証済) ため情報漏洩ではないが、無認証で容易に 500 を誘発できる堅牢性/DoS 上の問題。
- 設定面では `host_authorization: {permitted_hosts: ['.chip-atlas.org']}` が **Host が IP のリクエストを 403 で拒否** するため、ALB のヘルスチェック (既定で Host=IP) とデプロイスクリプトの疎通確認を壊す可能性が高い (production モードで実証)。
- rack-protection の既定 (HostAuthorization/HttpOrigin/JsonCsrf/PathTraversal/IPSpoofing/XSSHeader/FrameOptions) は有効。静的ファイルの traversal は PathTraversal で防御済。ただし CSP は未設定、170MB/44MB の JSON と source map が無認証配信。

深刻度別件数: **High 2 / Medium 4 / Low 5 / Info 4**

---

## SEC-BE-01 DataProxy 経由の同一ホスト任意パス取得 (オープンプロキシ) と巨大ファイルによるメモリ枯渇 DoS

- **深刻度**: High
- **種別**: SSRF / オープンプロキシ / DoS
- **場所**:
  - `lib/services/data_proxy.rb:55-66` (`fetch_live`: `uri.host == DATA_HOST` の後に `response.body` を全量取得)
  - `lib/services/location_service.rb:11-13,34-45,72-78` (`@genome`/`track`/`cell_type` を検査せず URL パスに連結)
  - `routes/api.rb:174-187` (`/api/colo/download`), `routes/api.rb:215-227` (`/api/target_genes/download`), `routes/api.rb:158-171` (`/api/colo`)
- **内容**: `LocationService#colo_tsv_url` 等は `"#{ARCHIVE_BASE}/#{@genome}/colo/#{track}.#{cell}.tsv"` という文字列を組み立てる。`@genome` はユーザ入力そのままで、`/` `..` `#` `?` を含められる。`DataProxy.fetch_live` のホスト検査は `URI.parse(url).host == 'chip-atlas.dbcls.jp'` のみで、**パスの正当性を一切見ない**。`#`/`?` を genome に入れると後続の `/colo/<track>.<cell>.tsv` がフラグメント/クエリに落ちて無視され、攻撃者が取得パスを完全に支配できる。取得本文は `response.body` で全量バッファリングされる。
- **攻撃シナリオ (ローカルで実証済)**:
  - `GET /api/colo/download?genome=util%2FlineNum.tsv%23&track=x&cell_type=y&format=tsv`
    → **200, 188434 バイトの `lineNum.tsv`** を返却 (コロカライゼーション TSV とは全く別のファイル)。
  - `GET /api/colo/download?genome=util%2FlineNum.tsv%3Fz=&track=x&cell_type=y&format=tsv` (`?` 版) も同結果。
  - `GET /api/target_genes/download?genome=util%2FlineNum.tsv%23&...` も 188434 バイトを返却。
  - `GET /api/colo?genome=hg38%2F..%2Fhg38&track=STAT3&cell_type=Blood` → 200 (同一ホスト内 `..` も通る)。
  - **メモリ枯渇 (未実行・実証はサイズ確認のみ)**: `genome=hg38/assembled/Oth.ALL.05.AllAg.AllCell.bed#` を与えると取得パスは同ファイルになる。`curl -sI` で当該ファイルの `Content-Length: 182361534663` (約182GB) を確認済。`DataProxy` は全量を `response.body` に読むため、これを指すと Puma プロセスが OOM。監査中、負荷でコンテナ (PID1=puma) が実際に停止しており、メモリ/時間圧に脆いことは確認済。
- **本番影響**: chip-atlas.dbcls.jp は無認証で公開されている同一組織のホストなので「秘密ファイルの窃取」自体の被害は限定的だが、(a) アプリを踏み台にした任意パス取得 (アプリ IP/評判の悪用、キャッシュ回避、ホットリンク)、(b) 182GB 級 .bed を指したメモリ枯渇でのサービス停止、が無認証で可能。ALB/nginx はパスを制限しないので緩和にならない。レート制限も無いため反復可能。
- **推奨対策**:
  - `genome`/`track`/`cell_type`/`distance` を厳格に検査 (genome は `Experiment.genomes.keys` のホワイトリスト、track/cell は `[\w.\-]` 等の許可文字集合)。`URI.encode_www_form_component` は既に track/cell に適用されているが genome/distance には未適用 (`location_service.rb:49,53,57,64` 系)。
  - `DataProxy` でホストに加え **パス接頭辞** (`/data/<genome>/...`) を検証し、`#`/`?`/`..` を拒否。`URI.parse` 後に `uri.path` を正規化して `/data/` 配下限定に。
  - `DataProxy` にレスポンスサイズ上限を設け、ストリーミング/`Content-Length` チェックで巨大本文を拒否 (例: 上限 50MB、超過で 502)。
- **確認状況**: `ローカルで実証済` (任意ファイル取得)。メモリ枯渇の到達性は `コード上の推定 + 巨大ファイルサイズ実測` (実ダウンロードは未実施)。

---

## SEC-BE-02 `/api/search` の入力長無制限による高コスト FTS クエリ DoS

- **深刻度**: High
- **種別**: DoS (リソース枯渇)
- **場所**: `routes/api.rb:94-101`, `lib/models/experiment_search.rb:94-124,150-157` (`search` / `fts5_sanitize`; `q` の長さ・トークン数制限なし、`COUNT(*) OVER()` 併用)
- **内容**: `/api/search` は `q` を無制限に受け取り、`fts5_sanitize` が空白区切りで各トークンをフレーズ化して MATCH に渡す。多数トークンのクエリは FTS5 の全走査に近くなり、加えて `COUNT(*) OVER() AS total_count` がヒット全件を数える。`limit` は 1..100 にクランプされるがスキャン量は減らない。Target Genes 側には `MAX_QUERY_LENGTH=200` があるのに、検索エンドポイントには相当する上限がない。
- **攻撃シナリオ (ローカルで実証済)**:
  - `q` = 同一語 "chip" を 1000 個空白連結 → **1 リクエストで 60 秒超** (curl の max-time 60 で打ち切り)。
  - `q` = 相異なる 1000 トークン → **約 37 秒**。
  - 通常語でも `q=seq`/`q=cell&offset=100000` で 0.7〜0.8 秒とやや重い。
  - Puma はスレッド数 5 (`config/puma.rb:17-18`)、`DB` の `pool_timeout: 300` (`lib/db.rb:7`)。数本の同時 30〜60 秒クエリでプールが埋まり、後続は最大 5 分キューされ実質全断。監査中に実際にインスタンス (puma=PID1) が停止した。
- **本番影響**: 無認証・低帯域で容易にワーカ枯渇 → サイト全停止。nginx `proxy_read_timeout 120s`、Puma `worker_timeout 60` は cluster 時のみ効き、単一クエリのコストは下がらない。ALB は上流の遅延を吸収できない。
- **推奨対策**:
  - `q` に長さ上限 (例 100〜200 文字) とトークン数上限 (例 16)。超過は切り詰めか 400。
  - SQLite に文単位タイムアウト (`sqlite3` の busy/`PRAGMA` やアプリ側 `Timeout`)、`COUNT(*) OVER()` を概算/上限付きに。
  - nginx/アプリ層でのレート制限 (SEC-BE-04 と共通)。
- **確認状況**: `ローカルで実証済`。

---

## SEC-BE-03 型混同パラメータ/JSON ボディによる未処理例外 (500) の多発

- **深刻度**: Medium
- **種別**: 入力検証不備 / 堅牢性 / (限定的) DoS
- **場所**:
  - `routes/api.rb:97-100` (`params[:limit].to_i` / `q.strip`: 配列で 500), `experiment_search.rb:95` (`query.strip`)
  - `routes/api.rb:135,140` → `location_service.rb:11` (`data['condition'].transform_keys`: 非 Hash で 500), `routes/api.rb:39-43` (`body_with_condition`)
  - `routes/jobs.rb:126-133` → `experiment.rb:201-206` (`total_number_of_reads`: `ids` が String/Integer/Hash/入れ子配列で 500)
  - `routes/pages.rb:29` (`params[:id].upcase`: 配列/不正 UTF-8 で 500)
  - `routes/api.rb:89-92` → `experiment.rb:185-190` (`/api/experiment` は id 検証なし。配列で SQLite datatype mismatch 500)
- **内容**: クエリ/JSON の値が想定型 (String/Array) と異なると Ruby の `NoMethodError`/`TypeError` や `Sequel::DatabaseError` が上がる。`JsonBodyParser` は配列・数値・真偽値・null もそのまま `parsed_body` に入れる (`lib/middleware/json_body_parser.rb:23`) ため、`parsed_json` の後段でハッシュ前提のコードが落ちる。
- **攻撃シナリオ (ローカルで実証済、抜粋)**:
  - `GET /api/search?q[]=a` → 500 `undefined method 'strip' for Array`
  - `GET /api/search?q=%FF` → 500 `JSON::GeneratorError: illegal/malformed utf-8`
  - `GET /api/search?offset=99999999999999999999` → 500 `SQLite3::MismatchException`
  - `POST /api/igv_url` ボディ `[1,2]` / `123` / `true` → 500 (`condition object required` の判定前に落ちる)
  - `POST /jobs/estimated_time` `{"ids":"SRX..."}` → 500 `undefined method 'map' for String`; `{"ids":{"a":1}}` → 500 `row value misused`
  - `GET /view?id[]=x` / `?id=%FF` → 500 (`upcase`)
  - `GET /api/colo?genome[]=hg38&...` → 500 (URL 生成前に配列が連結され `URI::InvalidURIError`)
- **本番影響**: **本番はスタックトレースを漏らさない** (production モードで実証: 全 500 が `<h1>Internal Server Error</h1>` 30 バイトのみ、`content-type: text/html`)。よって情報漏洩ではない。ただし無認証で任意に 500 を量産でき、エラー率悪化・監視ノイズ・一部は DB クエリまで到達するので軽微な負荷源。開発モードでは全バックトレース (`/app/...` パス込み) を返すため、誤って非 production で起動した場合は情報漏洩になる。
- **推奨対策**: 各ルート冒頭で `params[:x].is_a?(String)` を検査し 400 を返す。`JsonBodyParser` でトップレベルが Hash でなければ 400。`total_number_of_reads` は `ids` を Array かつ要素 String に限定。`to_i` に安全な範囲クランプ。
- **確認状況**: `ローカルで実証済` (500 応答本文まで確認)。本番の非トレース挙動も `production モードで実証済`。

---

## SEC-BE-04 無認証の計算ジョブ投入・レート制限の全面的欠如

- **深刻度**: Medium
- **種別**: 濫用 (資源/評判) / DoS / 認可
- **場所**: `routes/jobs.rb:51-75` (`POST /jobs/submit`), `lib/services/compute_router.rb:50-60`, `lib/services/wabi_service.rb:89-95,164-171` (`Net::HTTP.post_form` へ `data['params']||data` を転送), `lib/services/sapporo_service.rb:14-34`。nginx (`config/nginx/chip-atlas.conf`) にもアプリにもレート制限なし。
- **内容**: 認証・CAPTCHA・レート制限なしで、任意クライアントが DDBJ の WABI (`dtn1.ddbj.nig.ac.jp`) および WES (`ea.chip-atlas.org`) に計算ジョブを投入できる。サイズ上限は nginx `client_max_body_size 16m` のみ。`data['params'] || data` がそのまま `post_form` に渡るため、値が非文字列/入れ子だと `URI.encode_www_form` で例外 (500) にもなり得る。
- **攻撃シナリオ**: バックエンドが up の時に `/jobs/submit` を反復し、共有計算基盤 (国立 DDBJ) にジョブを大量投入 → 資源濫用・アプリ/組織の評判リスク。ローカルでは WABI が down 判定のため実投入は行っていない (`submit diff_analysis` → 503, `bogus type` → 503 を確認)。SEC-BE-01/02 と併せ、`/api/colo`・`/api/target_genes` (毎回データサーバへ数百KB〜数MB を fetch+parse; ColoTsv はキャッシュなし `colo_tsv.rb:47-56`) もレート制限なしで反復でき、データサーバへの増幅にもなる。
- **本番影響**: 外部基盤への濫用は本番でこそ実害。ALB/nginx に WAF/レート制限が無ければそのまま通る。
- **推奨対策**: `/jobs/submit` にレート制限・投入サイズ上限・(可能なら) 簡易な人手確認。WabiService へ渡す前に `params` の型/キーを検証。nginx `limit_req`/ALB WAF の導入。`WabiService.post` に送信サイズ上限。
- **確認状況**: `コード上の推定 + ローカルで一部実証` (実ジョブ投入は規約により未実施)。

---

## SEC-BE-05 host_authorization が ALB ヘルスチェック (Host=IP) を 403 拒否 → 可用性/デプロイ破綻リスク

- **深刻度**: Medium
- **種別**: 設定不備 / 可用性
- **場所**: `app.rb:70-72` (`configure :production { set :host_authorization, { permitted_hosts: ['.chip-atlas.org'] } }`), `config/nginx/chip-atlas.conf:56-65` (`location = /health` が `proxy_set_header Host $host`), `script/deploy/deploy.sh` (`wait_for_healthy` が `http://$NEW_INSTANCE_IP/health` を Host=IP で叩く)
- **内容**: production では Host が `*.chip-atlas.org` に一致しないと全ルートが 403。ALB のヘルスチェックは既定で Host にターゲット IP を送るため、nginx `location = /health` が Host=IP を Puma に転送 → **403 "Host not permitted"**。`/health` は host_authorization を迂回しない。
- **攻撃シナリオ (production モードで実証, rack-test)**:
  - `/health` Host=`chip-atlas.org` → 200、Host=`www.chip-atlas.org` → 200
  - `/health` Host=`10.0.3.14` (ALB by IP) → **403 "Host not permitted"**
  - `/health` Host=`chip-atlas.org.evil.com` → 403 (接尾辞バイパス不可、これは正しい挙動)
  - `/` Host=`evil.example` → 403
- **本番影響**: ALB がターゲットを常時 unhealthy と判定し、デプロイ (`deploy.sh` の IP 直叩きヘルスチェック) も失敗する恐れ。実ユーザ経路は ALB→nginx で Host=chip-atlas.org が保たれるため 200 で動くが、ヘルスチェック/IP 直アクセスが壊れる。なお本設定は sengu 版の新規追加であり、旧本番には無い (=デプロイ時に初めて顕在化する潜在バグ)。セキュリティ強化 (DNS リバインディング対策) 自体は妥当。
- **推奨対策**: (a) ターゲットグループのヘルスチェックに固定 Host (`chip-atlas.org`) を設定、または (b) `/health` を host_authorization から除外 (`allow_if` で `PATH_INFO == '/health'` を許可)、もしくは (c) permitted_hosts に運用上必要なホスト/内部名を追加。デプロイ後に `curl -H 'Host: chip-atlas.org' http://<ip>/health` で検証。
- **確認状況**: `production モードで実証済` (rack-test / Rack::MockRequest)。ALB 実機の Host 送出設定は `要追加検証`。

---

## SEC-BE-06 巨大静的ファイルの無認証配信と source map 公開 (帯域 DoS / 情報開示)

- **深刻度**: Medium
- **種別**: DoS (帯域) / 情報漏洩
- **場所**: `public/ExperimentList_adv.json` (約170MB), `public/ExperimentList.json` (約44MB), `public/js/*.js.map` (12ファイル), `public/analysisList.tab`。配信は Sinatra 静的 (`static` 既定 on) 及び本番 nginx `location /` の `try_files $uri @app` (`config/nginx/chip-atlas.conf:79-81`, `/js/` は `:26-30`)。
- **内容**: `HEAD /ExperimentList_adv.json` → 200 (170MB), `HEAD /ExperimentList.json` → 200 (44MB), `GET /js/search.js.map` → 200 (原 TypeScript のパス構造を含む source map), `GET /analysisList.tab` → 200。アプリは DB からデータを読むため、これら巨大 JSON は新版では未使用の可能性が高く、純粋な負債。
- **攻撃シナリオ**: 無認証で 170MB を反復取得 → 帯域/転送費の増幅 DoS。source map から原 TS のディレクトリ構成・ロジックが読める (ただし本プロジェクトは OSS 公開のため機密性は低い)。
- **本番影響**: nginx が直接配信するので高速だが、レート制限が無いため帯域濫用は成立。source map 情報開示は OSS ゆえ影響小。
- **推奨対策**: 未使用の巨大 JSON を `public/` から削除 (`.gitignore` に `experimentList*json` はあるが `ExperimentList*.json` は追跡外でも物理配置されている)。本番で `.map` を配信しない (nginx で `location ~ \.map$ { return 404; }`)、または deploy 時に除外。大容量ファイルにレート制限。
- **確認状況**: `ローカルで実証済` (HEAD/GET のステータス・サイズ確認)。

---

## SEC-BE-07 Gemfile にバージョン制約が一切ない (供給網 / 再現性)

- **深刻度**: Low
- **種別**: 依存関係 / 供給網
- **場所**: `Gemfile:1-24` (全 gem が制約なし), `Gemfile.lock` (rack 3.2.5, sinatra 4.2.1, puma 7.2.0, rexml 3.4.4, kramdown 2.5.2, sqlite3 2.9.1, sequel 5.103.0, erubi 1.13.1, nio4r 2.7.5)
- **内容**: `Gemfile` にバージョン指定が無く、`Gemfile.lock` のみが固定源。ローカル開発コンテナは起動毎に `bundle install` を実行 (`~/run/chip-atlas-local.sh`) するため、lock が無い/更新される状況では最新版を引き込みうる。現行 lock の各版は比較的新しく、当方の知識 (2026-06 時点) で確度高く該当する既知脆弱性は把握していない。REXML 3.4.4 はエンティティ展開系 CVE への対策済で、XML は NCBI 由来かつ id は検証済 (SEC-BE-Info 参照) のため XXE リスクは低い。
- **本番影響**: 本番デプロイは `bundle install --deployment` (`deploy.sh`) で lock 準拠のため直接の危険は小。ただし制約が無いと lock 再生成時にメジャー跳躍を検知できず、将来の脆弱バージョン混入・再現性低下のリスク。
- **推奨対策**: 主要 gem に悲観的バージョン制約 (`~>`) を付与。CI に `bundler-audit` を組み込み既知脆弱性を継続監視。
- **確認状況**: `コード上の推定` (lock の版は確認済、CVE 照合は当方知識の範囲)。

---

## SEC-BE-08 開発モードでのスタックトレース全出力 / CSP 未設定

- **深刻度**: Low
- **種別**: 情報漏洩 (設定依存) / ヘッダ強化不足
- **場所**: Sinatra 既定 (`show_exceptions = development?`, `raise_errors = test?`, `dump_errors = !test?`)。アプリ側で上書きなし (`app.rb` に `set :show_exceptions/:protection` 等の記述なし)。`config/puma.rb:8` は `ENV.fetch('RACK_ENV','production')`。CSP は rack-protection の `ContentSecurityPolicy` が既定 off。
- **内容**: production では 500 が generic 本文のみ (SEC-BE-03 で実証) だが、非 production で起動すると全バックトレース (`/app/lib/...` の絶対パス込み) を返す。ローカル (development) では現に多数の 500 でトレースが露出。CSP ヘッダは付与されない (`/` の応答に `content-security-policy` 無し、XFO/XCTO/XXSS のみ実測)。
- **本番影響**: `RACK_ENV=production` が守られていれば漏洩なし。運用ミスで環境変数が外れると即漏洩するため、明示的な `set :show_exceptions, false` / `set :dump_errors, false` によるフェイルセーフが望ましい。CSP 欠如は、`<%==` の生 HTML 出力箇所 (いずれも JSON/静的 markdown で現状は安全) に対する多層防御が薄いこと。
- **推奨対策**: `app.rb` で production 相当設定を明示 (`configure { set :show_exceptions, false; set :dump_errors, false }`)。nginx かアプリで CSP を付与。
- **確認状況**: `production/development 双方で実証済`。

---

## SEC-BE-09 `/api/remote_url_status` は allowlist 堅牢だが任意ポート/パスへの HEAD が可能

- **深刻度**: Low
- **種別**: SSRF (限定的)
- **場所**: `routes/api.rb:13-19` (`allowed_remote_url?`), `routes/api.rb:231-254`
- **内容**: allowlist は `uri.host == host || uri.host.end_with?(".#{host}")` で実装され、代表的バイパスを全て弾く (下記実証)。ただし許可ホスト (`chip-atlas.dbcls.jp`, `dtn1.ddbj.nig.ac.jp`) に対しては **任意ポート・任意パスへの HEAD** が可能で、応答コードのみ返す。リダイレクト追従は無し (`request_head` 単発)。
- **攻撃シナリオ (ローカルで実証済, いずれも 400 拒否)**: userinfo `https://chip-atlas.dbcls.jp@example.com/`、接尾辞 `...jp.example.com`、接頭辞 `xchip-atlas...`、バックスラッシュ `...jp%5C@evil`、`ftp://`、ホスト無し `https:///x`、配列 `url[]=`。許可ホストは `:8443` (→502) や `http://.../robots.txt` (→302) が通る。
- **本番影響**: 対象が 2 ホストに限定され、返るのは HTTP ステータスコードのみのため、内部ネットワーク探索には使えず、当該 2 ホストのポート/パス存在確認・タイミング差の観測に留まる。実害は小。
- **推奨対策**: 用途に足るなら固定パスのみ許可 (パスも allowlist)、ポートを 443 に限定。
- **確認状況**: `ローカルで実証済`。

---

## SEC-BE-10 SraService のエラーメタデータ 30日キャッシュ / TSV 再取得・パース増幅

- **深刻度**: Low
- **種別**: DoS (増幅) / データ品質
- **場所**: `lib/services/sra_service.rb:16-23,93-111` (NCBI 失敗時に `error_metadata` を返し `SraCache.set`), `lib/models/sra_cache.rb:24-35` (TTL 30日), `lib/services/colo_tsv.rb:47-56,100-109` (キャッシュ無しで毎回 fetch+parse), `lib/services/target_genes_tsv.rb:60-64` (150MB バイト予算キャッシュ)
- **内容**: `/view` は `id_valid?` (DB 実在) を満たす id のみ NCBI へ問い合わせるため、**任意 id によるキャッシュ汚染や sra_cache 無限増殖は成立しない** (id 集合は約45万で有限、ここは良い設計)。ただし NCBI 一時失敗時も `error_metadata` (truthy) が `set` され、当該 id は 30日間エラーで固定される。`/api/colo` はキャッシュせず毎回データサーバへ fetch+parse するため、レート制限欠如 (SEC-BE-04) と併せデータサーバ/CPU への増幅要因。
- **本番影響**: 個々は軽微。エラー固定は一時障害後もその実験ページの NCBI 情報が 30日欠落する UX 劣化。
- **推奨対策**: `error_metadata` は短 TTL でキャッシュするか非キャッシュに。`/api/colo` にも短時間キャッシュ。
- **確認状況**: `コード上の推定`。

---

## SEC-BE-11 ログ書き込みの request.ip / action (ログ汚染は限定的)

- **深刻度**: Low
- **種別**: ログ / なりすまし (限定的)
- **場所**: `app.rb:56-60` (`log_activity`: `request.ip` と `JSON.generate(data)` を TAB 連結して `log/access_log` に追記), 各ルートの `log_activity(...)` 呼び出し
- **内容**: 可変フィールドは `request.ip` と `action`、及び `data`。`data` は `JSON.generate` されるため改行・タブは `\n`/`\t` にエスケープされ、TSV 行注入は防がれる (実測: `q` に `%0a`/`%09` を入れてもログは JSON エスケープ済)。`action` は GET 系では固定文字列、`parsed_json` 経由では `request.path_info` (マッチ済ルートのパス) で安全。`request.ip` は本番では nginx が付与する `X-Forwarded-For` を Rack が解釈するため、クライアントが XFF を前置して IP を偽装しうる (Rack は IP 形式は検証)。ローカルでは REMOTE_ADDR (`192.168.65.1`) が記録され XFF 偽装は反映されなかった。
- **本番影響**: ログ上の送信元 IP を偽装可能な程度。改行注入による偽ログ行生成は JSON エスケープで防止済。
- **推奨対策**: 信頼するプロキシ段数を明示 (Rack の `trusted proxies`/`Forwarded` 設定) し、記録 IP を nginx の `X-Real-IP` (単一) に限定。
- **確認状況**: `ローカルで実証済` (エスケープ挙動)。本番の XFF 挙動は `コード上の推定`。

---

## 問題なしと確認した項目 (監査済みで安全と判断)

- **SQL インジェクション**: Sequel のデータセット API とプレースホルダ (`experiment_search.rb:83-90,108,117,136,144`, `experiment.rb:204-206`, `bedfile.rb:26-35` 等) で全てパラメタライズ。`clean_old_genomes.rake:70` の生 INSERT も `DB.literal` でエスケープ+固定カラム名 (オフライン rake、非公開)。ユーザ入力から SQL を組む箇所なし。SQLi は不成立。
- **FTS5 構文インジェクション**: `fts5_sanitize` (`experiment_search.rb:150-157`) が `" ' ( ) * ^ { } :` を除去しトークンをフレーズ化。`CTCF"`, `NEAR(`, `*`, `-`, `title:CTCF`, `CTCF; DROP TABLE...` など多数を投げても構文破壊/500 なし (正常 200)。
- **静的ファイルのパストラバーサル**: `PathTraversal` middleware が有効。`/js/%2e%2e/Gemfile`, `/%2e%2e%2f%2e%2e%2fetc%2fpasswd`, `--path-as-is` 版、いずれも 404。`views/layout.erb`, `log/access_log`, `database.sqlite.verify` も 404 (Sinatra `static!` が public 配下限定 `File.expand_path` チェック)。
- **`attachment` ヘッダインジェクション**: Sinatra `attachment` が `File.basename` + `"`/CR/LF 置換を行うため、`track`/`cell_type`/`format` からの Content-Disposition/ヘッダ分割は不成立 (`api.rb:185,225`)。到達には実在ファイルの取得成功も必要。
- **redirect ヘッダインジェクション**: `/view` の `redirect "/view?id=#{srx}"` (`pages.rb:32`) の `srx` は DB 由来 (`gsm_to_srx`)。`@expid` は `id_valid?` を通過した実在 id のみテンプレートに到達。
- **XSS (サーバ描画)**: erb は `escape_html: true`。生出力 `<%==` は全て `{...}.to_json.gsub('</','<\/')` の JSON script ブロックか、リポジトリ同梱の静的 markdown の Kramdown 変換 (`views/{about,publications,agents,demo}.erb`) で、リクエスト毎のユーザ/DB データを生では出さない。`@expid` は検証済 id。
- **rack-protection 既定**: HostAuthorization / HttpOrigin / JsonCsrf / PathTraversal / IPSpoofing / XSSHeader / FrameOptions が有効 (実測ヘッダ XFO=SAMEORIGIN, XCTO=nosniff, XXSS=1; mode=block)。`method_override` 既定 off (実測 `_method=DELETE` は無効、`POST /api/genomes` → 404)。JSON CSRF は認証が無いため実害はないが有効。
- **HTTP メソッド**: 未定義メソッド/パスは 404。`OPTIONS /`, `TRACE /`, `POST` を GET 専用ルートへ → 404/405 相当で安全。HEAD は Rack::Head で 200 (本文空)。
- **キャッシュ増殖**: `BedExtensionResolver` (最大2000, FIFO, ARCHIVE_HOST 限定), `TargetGenesTsv` (150MB バイト予算, FIFO), `Experiment` index (TTL 1h), `sra_cache` (実在 id に限定) はいずれも上限付きで無限増殖しない。

## 未確認・不確実事項

- **WABI/WES への実ジョブ投入経路** (`WabiService.submit_job` の `post_form` 型混同 500 や実際の投入挙動): 規約により外部基盤へ投げていないため `コード上の推定`。ローカルではバックエンド down 判定で 503 手前で止まる。
- **DataProxy 経由 182GB ファイルでの実 OOM**: 巨大ファイルの実ダウンロードはサーバ/回線を害するため未実施。任意パス取得の成立と `Content-Length` 実測までで、OOM 到達は推定。
- **ALB 実機のヘルスチェック Host 送出設定** (SEC-BE-05): production モードの 403 挙動は実証済だが、ALB ターゲットグループが Host をどう送るか (既定 IP か、カスタム Host 設定済か) は本番設定次第で `要追加検証`。
- **本番 nginx の実レート制限/WAF 有無**: 提供された `config/nginx/chip-atlas.conf` にはレート制限が無いが、ALB/上位に WAF がある可能性は未確認。
- **本番の実際の依存バージョン・OS パッチ状況**: `deploy.sh` は `apt upgrade` と `bundle install --deployment` を行うが、稼働中インスタンスの実バージョンは未確認。既知 CVE 照合は当方知識 (2026-06 時点) の範囲での判断。
- **ブラウザ依存の検証** (BRIEF ルール2): CSP 欠如下での実 XSS 実行可否、フロントの DB データ描画箇所 (SEC-FE 範囲) は本監査対象外。
