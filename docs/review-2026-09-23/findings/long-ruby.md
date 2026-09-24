# LONG-RB: Ruby コードから見た「10 年無人運用」リスク (ChIP-Atlas sengu ブランチ)

対象: `app.rb`, `config.ru`, `routes/*.rb`, `lib/**/*.rb`, `lib/tasks/*.rake`, `Rakefile`, `db/migrations/*.rb`, `Gemfile(.lock)`, `test/**` (カバレッジ判定のみ)。
検証手段: 全ファイル通読、`database.sqlite.verify` への読み取り専用 sqlite3 クエリ、`chip-atlas-local` コンテナ内での `bundle exec ruby` (Rack::MockRequest で本番モードを再現、gem ソース確認、メモリ計測)、localhost:9292 への軽量 GET。リポジトリは変更していない。

## 担当範囲の要約と総評

- Ruby コード自体は小さく (lib+routes+app で約 3,300 行)、Ruby 4.0.5 / Sinatra 4.2 / Rack 3.2 / Sequel 5.103 の API 使用に非推奨・削除済みのものは見つからなかった。bundled gem 化された `logger`/`base64`/`bigdecimal`/`rexml` は Gemfile.lock に入っており、`csv`/`ostruct` 等は未使用。FTS5 検索のサニタイズは 21 種の境界クエリ全てに 200 を返し堅牢。
- 一方で「人が手を入れないと動き続けない」要因は **運用面に集中**している。(1) 本番設定の `host_authorization` が `*.chip-atlas.org` 以外の Host に 403 を返すため、ALB ヘルスチェックや IP 直叩きの `/health` が通らず、初回デプロイで詰まる可能性が高い。(2) `rake metadata:load` は稼働中 DB のテーブルをトランザクション外で DELETE してから数分かけて再投入するため、更新中サイトが空になり、途中失敗すると空のまま残る。更新後の再起動・スナップショット掃除・実行ホストの要件 (RSS 1.1 GB 超) はどこにも書かれていない。(3) `log/access_log` に POST ボディ全文 (Enrichment Analysis の BED 内容、最大 16 MB) を書き、日次ローテーション後の削除は無し。`log/puma.stderr.log` は無限追記。(4) `script/deploy/deploy.sh` と `script/systemctl/` は旧アプリ (unicorn, `rake pj:load_metadata`) 前提で、新アプリでは必ず失敗し、再起動時に Puma を起動する仕組みがリポジトリに無い。
- サイレント障害の中心は `SraService`: NCBI の一時障害・429・0 件を `error_metadata` として **30 日キャッシュ**し、`OpenSSL::SSL::SSLError` や `ECONNRESET` は rescue されず /view が 500 になる。`DataProxy` は上流の全障害を nil → 404 "not found" に変換し、`/status` の feature フラグはフロントエンドのどこからも参照されていない。
- Ruby/gem の寿命: Gemfile にバージョン制約が無く、`Gemfile.lock` の `BUNDLED WITH 2.5.3` は Ruby 4.0.5 同梱の Bundler 4.0.10 と食い違い、`sqlite3 2.9.1` のネイティブ gem は Ruby < 4.1 限定。Ruby 4.0 の保守終了 (2029 年頃) までに 1 回、10 年で 2〜3 回は Ruby とネイティブ gem の更新作業が避けられない。
- 総評: コードは「外部が変わらなければ」概ね動き続けるが、**デプロイ・データ更新・ログ・再起動の 4 手順が新アプリ用に整備されていない**ため、現状のままでは初回デプロイ時と初回データ更新時に人手が必要になる。高 5 件、中 8 件、低 13 件。

---

## 高

### LONG-RB-01 本番の host_authorization が ALB ヘルスチェック / IP 直叩きの /health を 403 にする
- **リスク度**: 高
- **顕在化時期**: 初回デプロイ時 (ALB ターゲット登録時) / インスタンス入れ替え時
- **場所**: `app.rb:70-72` (`set :host_authorization, { permitted_hosts: ['.chip-atlas.org'] }`), `config/nginx/chip-atlas.conf:56-58` (`/health` を `Host $host` のまま転送), `script/deploy/deploy.sh:283-284` (`curl http://$IP/health`)
- **内容**: Sinatra 4.1+ の `host_authorization` は Rack::Protection::HostAuthorization を挿入し、許可外 Host に 403 "Host not permitted" を返す。本番モードで `Rack::MockRequest` により再現: `Host: chip-atlas.org` → 200、`Host: www.chip-atlas.org` → 200、`Host: 10.0.0.5` / `10.0.0.5:80` / `localhost:9292` → 403、`X-Forwarded-Host: chip-atlas.org` を付けても 403。ALB のヘルスチェックはターゲット IP を Host に載せる (AWS の仕様) ので、nginx を経由しても Puma で 403 になり、ターゲットは unhealthy のまま登録されない。`deploy.sh:283` の IP 直叩きも同じ理由 (加えて nginx :80 は `return 301` なので 301) で 5 分待って `die`。旧アプリには host 制限が無かったため、この経路は一度も実運用で通っていないと推定。運用者から見ると「デプロイが health check で止まる」「ALB が全ターゲット unhealthy」。
- **推奨対策**: `host_authorization` に `allow_if: ->(env) { env['PATH_INFO'] == '/health' }` を追加する (Rack::Protection::HostAuthorization は `:allow_if` を受け付ける: `rack-protection/host_authorization.rb:30,56`)。または nginx の `/health` location で `proxy_set_header Host chip-atlas.org;` に固定する。deploy.sh の待機は `-H 'Host: chip-atlas.org'` と `-k https://` に変える。
- **確認状況**: `ローカルで再現` (MockRequest, RACK_ENV=production)。ALB 側の Host 値は `推定` (AWS 仕様に基づく)。

### LONG-RB-02 `rake metadata:load` は稼働中 DB を数分間「空」にし、失敗すると空のまま残す。更新手順が未文書化
- **リスク度**: 高
- **顕在化時期**: 初回データ更新時 (以後毎回)
- **場所**: `lib/tasks/metadata.rake:89-91` (`DB[:experiments].delete; DB[:experiments_fts].delete` の後に `load_from_files`), 同 `:104`, `:112`, `:131` (bedfiles/analyses/bedsizes も同型), `lib/models/experiment.rb:291` (INSERT 側だけ `DB.transaction`), `routes/health.rb:19-22` (`experiments: 'empty'` でも 200), `SHIKINEN-SENGU.md:551-556` (手順は「`rake metadata:load` を再実行」のみ)
- **内容**: DELETE は各々オートコミットされ、WAL モードの読み手は即座に空テーブルを見る。その後 `load_json_index` (実測 2.2 s, RSS 845 MB) と 867,660 行のタブ読込・INSERT が 1 トランザクションで走る間、ユーザには「Home の実験数 0」「検索 0 件」「/view が全部 404」「Peak Browser のメニュー空」が見える。ロードが例外で止まると (例: 不正 UTF-8 が 1 バイトでもあると `split("\t")` が `ArgumentError: invalid byte sequence` を投げる — コンテナで確認。現行スナップショットは 0 行) DELETE 済みのまま終わり、`/health` は `database: ok` で 200 を返し続けるので LB は異常を検知しない。また稼働中に `rake` を同一ファイルへ走らせると、ロード中の `SraCache.set` (`/view` のキャッシュミス時) が SQLite の busy_timeout 5 s (Sequel 既定, `sequel/adapters/sqlite.rb:150`) 超過で `Sequel::DatabaseError` → /view が 500。プロセス内キャッシュ (RB-09) も更新されない。メモリの `database.sqlite.latest/.rebuild/.verify` という別ファイル運用はローカルの慣行で、手順としてはどこにも書かれていない。
- **推奨対策**: (a) `metadata.rake` の DELETE を各ローダの `DB.transaction` 内に移す (INSERT と同一トランザクションにすれば読み手は旧→新へ原子的に切り替わる)。(b) 手順を文書化: `DATABASE_URL=sqlite://database.sqlite.new rake db:migrate metadata:load` → `mv` で差し替え → Puma 再起動 (`kill -USR2` or systemd restart)。(c) `/health` で `experiments == 0` を 503 にする (ALB が空インスタンスを外せる)。(d) ローダで `line.scrub` するか、不正行を数えて警告する。
- **確認状況**: `ソース/設定で確認済み` (DELETE の位置)、`ローカルで再現` (不正 UTF-8 で ArgumentError, メモリ計測)。

### LONG-RB-03 access_log に POST ボディ全文を記録、ローテーション後の削除無し、puma.stderr.log は無限追記
- **リスク度**: 高
- **顕在化時期**: 数ヶ月〜数年 (投入量次第)
- **場所**: `app.rb:49-54` (`parsed_json` → `log_activity(request.path_info, data)`), `app.rb:56-60` (`JSON.generate(data)` を 1 行として書く), `app.rb:65` (`Logger.new('log/access_log', 'daily')`), `config/puma.rb:32` (`stdout_redirect ..., true` = 追記), `frontend/pages/enrichment-analysis.ts:604,621` (`bedAFile`/`bedBFile` にアップロードした BED の全文を載せる), `config/nginx/chip-atlas.conf:23` (`client_max_body_size 16m`)
- **内容**: `/jobs/submit` に届く JSON には Enrichment Analysis の BED ファイル内容がそのまま入っており、`parsed_json` がそれを丸ごと `log/access_log` に書く (1 投入で最大 16 MB)。Ruby Logger の `'daily'` はファイル名に日付を付けて残すだけで削除しない (`logger/log_device.rb:216-231` `shift_log_period` に unlink 無し; ローカルの `log/` に 4 月以降の `access_log.YYYYMMDD` が 6 本残っているのがその証拠)。`log/puma.stderr.log` は Puma 側でローテーションが無く、本番では Sinatra の `dump_errors=true` (MockRequest で確認) により **500 のたびにバックトレースが追記**される。RB-05/07 のような恒常的 500 が発生すると 1 リクエスト数 KB × クローラのアクセスで日単位で GB 級になり得る。ディスクが埋まると SQLite の `sra_cache` 書込みと nginx が先に壊れる。リポジトリに logrotate 設定は無い。
- **推奨対策**: `log_activity` はサイズ上限 (例: 1 KB) で切るか、`bedAFile`/`bedBFile`/`genes` 等の本文キーを除外して件数だけ記録する。Logger を `Logger.new(path, 30, 50 * 1024 * 1024)` (世代数×サイズ) にするか、logrotate (`copytruncate`) を deploy 手順に含める。Puma は `stdout_redirect` をやめて systemd/journald に任せる。
- **確認状況**: `ソース/設定で確認済み`、`ローカルで再現` (dump_errors 値、Logger ソース)。

### LONG-RB-04 デプロイ / 再起動手順が旧アプリ (unicorn) 前提のまま。新アプリを起動・更新する手順がリポジトリに無い
- **リスク度**: 高
- **顕在化時期**: 初回デプロイ時 / 初回再起動時 (OS 再起動・インスタンス入れ替え)
- **場所**: `script/deploy/deploy.sh:253` (`bundle exec rake pj:load_metadata` — 存在しないタスク。`Rakefile`/`lib/tasks/metadata.rake` は `metadata:load`), `:256-261` (`unicorn.rb` / `tmp/pids/unicorn.pid`; Gemfile に unicorn 無し), `:234` (`git reset --hard origin/master` — 新アプリは sengu ブランチ, master より 201 コミット先), `script/systemctl/chip-atlas:18` (unicorn), `docker-compose.yml` (`restart:` 無し), `.github/workflows/deploy.yml:60` (この deploy.sh を呼ぶ)
- **内容**: 担当範囲外のスクリプトだが、Ruby アプリの起動・更新に直結するため記載する。`set -euo pipefail` 下で `rake pj:load_metadata` が "Don't know how to build task" で失敗し、プロビジョニングはそこで止まる。仮に直しても `unicorn` 起動は失敗し、Puma を起動・自動再起動する systemd unit がどこにも無い (`docs/setup.md` は Ruby 2.5.1 + unicorn の手順)。docker 運用でも `restart: always` が無いのでホスト再起動でコンテナは戻らない。運用者から見ると「GitHub Actions の Deploy が Step 5 で失敗」「再起動後にサイトが落ちたまま」。
- **推奨対策**: deploy.sh を `rake db:migrate metadata:load` (RB-02 の別ファイル方式) + `systemctl restart chip-atlas` に書き換え、`config/puma.rb` を使う systemd unit (`WorkingDirectory=/home/ubuntu/chip-atlas`, `ExecStart=bundle exec puma -C config/puma.rb`, `Restart=always`) を `script/systemctl/` に置く。docker-compose.yml に `restart: unless-stopped`。`script/maintenance/smoke_test.sh` は旧エンドポイント (`/data/*`, `/wabi_chipatlas`, `/browse`) を叩くので新 API へ書き換える。
- **確認状況**: `ソース/設定で確認済み` (タスク名・unicorn 参照)。deploy.sh が旧アプリでも成功したことがあるかは `推定`できない (未確認事項参照)。

### LONG-RB-05 SraService: NCBI の一時障害を 30 日キャッシュし、SSL/接続リセットは 500、最悪 50 s リクエストスレッドを占有
- **リスク度**: 高
- **顕在化時期**: 特定条件 (NCBI の遅延・429・証明書変化・クローラによる /view 大量アクセス)
- **場所**: `lib/services/sra_service.rb:16-23` (`SraCache.set(@experiment_id, metadata) if metadata` — `fetch_from_ncbi` は失敗時も `error_metadata` の Hash を返すので常に真), `:37-48` (`rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, REXML::ParseException` のみ), `:50-59` (`get_uid` は `Errno::ECONNREFUSED` すら rescue せず), `:27-35` (`http_get` は非 200 を nil に), `lib/models/sra_cache.rb:7` (`TTL_SECONDS = 30 日`), `routes/pages.rb:37` (リクエストスレッド内で同期呼出), `views/experiment.erb:94-103,107-116`
- **内容**: 確認済み: `error_metadata` は truthy な Hash なので **NCBI のタイムアウト・429 (API キー無し、3 req/s 制限)・5xx・esearch 0 件のいずれも 30 日間 `sra_cache` に保存**され、その実験ページの "Sequenced DNA Library" / "Sequencing Platform" 表の全行に "ERROR: cannot retrieve data from NCBI" が 30 日表示される (erb は値が全て `''` の時だけ "No ... information was found" を出す)。クローラが /view を舐めて NCBI に 429 を出されると、数万ページ分のエラーが一斉に 30 日固定される。さらに `OpenSSL::SSL::SSLError`・`Errno::ECONNRESET`・`EOFError`・`Errno::EHOSTUNREACH` は rescue されず /view が 500 (+ RB-03 のバックトレース追記)。1 ページで esearch+efetch を直列に呼び、各 open 10 s + read 15 s なので最悪 50 s、Puma 2×5=10 スレッドが NCBI 待ちで埋まると `/health` まで応答不能になる (RB-13)。
- **推奨対策**: `fetch` で `metadata[:library_layout] == 'ERROR...'` のような失敗判定をして **失敗はキャッシュしない** (または 10 分程度の短い TTL で別保存)。`rescue StandardError` 相当 (`OpenSSL::SSL::SSLError, SystemCallError, IOError, Net::ProtocolError`) に広げる。タイムアウトを open 3 s / read 5 s に下げる。NCBI 取得をページ描画から外し、フロントエンドから `/api/sra_metadata?id=` を非同期取得する。`tool`/`email` パラメータと API キーを付ける。
- **確認状況**: `ソース/設定で確認済み` (キャッシュ条件、rescue 範囲、erb 表示)。429 の発生頻度は `推定`。

---

## 中

### LONG-RB-06 `metadata/` スナップショットが実行ごとに約 660 MB 蓄積し、`rake metadata:load` の常駐メモリは 1.1 GB を超える
- **リスク度**: 中
- **顕在化時期**: 数ヶ月〜数年 (更新頻度次第)、小さいインスタンスでは初回データ更新時
- **場所**: `lib/tasks/metadata.rake:19-20` (`metadata/<YYYYMMDD-HHMM>/` を毎回新規作成), `:6-16` (`response.body` 全体をメモリに持ってから `File.write`), `lib/models/experiment.rb:415-416` (`JSON.parse(File.read(json_path))`)
- **内容**: 2026-09-13 スナップショットは experimentList.tab 353 MB + ExperimentList_adv.json 171 MB + fileList.tab 139 MB ≒ 660 MB。削除ロジックが無いので月次更新なら年 8 GB、10 年で 80 GB。ローカルにも 6 ディレクトリ 1.6 GB が残っている。コンテナで計測: `load_json_index` 後 RSS 845 MB、さらに tab 本体 337 MB を保持した時点で 1,072 MB (Ruby はヒープを OS に返さない)。`docs/setup.md` の旧構成 (512 MB swap) 級のインスタンスでは OOM か長時間スワップ。要件はどこにも書かれていない。
- **推奨対策**: rake 完了時に最新 2 世代以外を削除する task を追加 (または `metadata_dir` 固定 + `file` タスクの mtime 判定に任せる)。`download_file` はストリーミング書込 (`Net::HTTP#get` にブロックを渡す)。JSON は `JSON.parse` 後に不要な列を落とすか、`JSON::Stream`/行単位に。必要メモリ (2 GB 以上) を README に明記。
- **確認状況**: `ローカルで再現` (メモリ計測)、`ソース/設定で確認済み` (削除無し)。

### LONG-RB-07 外部 HTTP の rescue 漏れ (SSL / ECONNRESET / EOF) と WABI POST のタイムアウト未設定 → 500
- **リスク度**: 中
- **顕在化時期**: 特定条件 (上流の接続リセット、TLS 変化、コンテナ内 CA バンドルの経年劣化)、数年
- **場所**: `lib/services/data_proxy.rb:67` (`rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError`), `lib/services/wabi_service.rb:116,147` (同型), `:164-171` (`Net::HTTP.post_form` — open/read 60 s 既定、rescue 無し), `lib/services/sapporo_service.rb:32,53,76`, `lib/services/sra_service.rb:46,57`, `routes/api.rb:250-251` と `lib/services/service_monitor.rb:82-83` (こちらは SSLError を rescue している — 不揃い)
- **内容**: `Net::HTTPError` は `Net::HTTPResponse#value` でしか発生しないので実質無意味で、実際に起きる `OpenSSL::SSL::SSLError`・`Errno::ECONNRESET`・`Errno::EHOSTUNREACH`・`EOFError` が素通りする。Docker イメージの `ca-certificates` はビルド時のまま固定されるため、10 年の間に上流のルート CA が入れ替わると (2021 年の DST Root X3 期限切れ型) **/api/colo・/api/target_genes・両 download・/view・/jobs/:id/status が一斉に 500** になり、`/status` だけが 'down' を報告する (誰も見ていない: RB-08)。WABI 投入は `ServiceMonitor` が 60 s キャッシュで 'ok' と言っている間に WABI がハングすると最大 120 s スレッドを塞ぎ、nginx の 120 s で 504。
- **推奨対策**: 共通の HTTP ヘルパー (1 箇所) に `rescue OpenSSL::SSL::SSLError, SystemCallError, IOError, Timeout::Error, Net::ProtocolError` とタイムアウトをまとめる。`post_form` を `Net::HTTP.new` + `open_timeout/read_timeout` 付きに置換。Dockerfile で `apt-get install -y ca-certificates` を更新に含め、イメージ再ビルドを年次作業として明記。
- **確認状況**: `ソース/設定で確認済み`。CA 劣化の時期は `推定`。

### LONG-RB-08 DataProxy が上流の全障害を 404 "not found" に変換し、`/status` の feature フラグはフロントエンドが一切参照しない
- **リスク度**: 中
- **顕在化時期**: 特定条件 (chip-atlas.dbcls.jp の遅延・5xx)
- **場所**: `lib/services/data_proxy.rb:65-68` (非 200 と例外を nil に), `routes/api.rb:167,183,208,223` (nil → `halt 404 'not found'`), `lib/services/service_monitor.rb:38-63` (`features:` を組む), `routes/health.rb:27-40` (`/status`), `frontend/api/client.ts:461` (`getServiceStatus` は定義のみ、`frontend/pages` `frontend/components` に呼出し無し), `frontend/pages/diff-analysis.ts:218-233` (`/jobs/available` は fail-open)
- **内容**: データサーバが 503/タイムアウトを返しても API は「Colocalization data not found」(404) を返し、結果ページは `#error-state` の汎用エラー表示になる。監視 (5xx 率) には現れず、運用者は「そのアンチジェンのデータが無い」と誤読する。`ServiceMonitor` が 60 s ごとに `experimentList.tab` へ HEAD して作る `peak_browser/colo/target_genes: 'unavailable'` は `/status` を GET する者しか見えず、UI はバナーも無効化もしない。ジョブ系の 503 `backend_unavailable` は `client.ts:214-216` が非 2xx で throw するため `job-tracker.ts:215` の FAILED 分岐に届かず (RB-21)。つまり ServiceMonitor の存在意義は `ComputeRouter` の wabi/wes 切替だけ。
- **推奨対策**: `DataProxy.fetch` を `[body, status]` か例外 (`UpstreamError`) を返す形にし、ルートで 404 (上流 404) と 502/503 (それ以外) を分ける。`/status` を使うか、使わないなら `ServiceMonitor` の data_server チェックと `features` を削る (無駄な 60 s ごとの外部 HEAD をやめる)。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-09 プロセス内キャッシュがデータ更新後も再起動まで残る (検索総件数は永久、ゲノム一覧は起動時固定)
- **リスク度**: 中
- **顕在化時期**: 初回データ更新時 (再起動しなかった場合)
- **場所**: `lib/models/experiment_search.rb:72-87` (`total_count_cache` は `reset_total_count_cache!` でしか消えず、それを呼ぶ `experiment.rb:404` は rake プロセス側), `lib/models/experiment.rb:32-34,107-116` (`cached_index_all_genome` TTL 1 h), `:36-38,67-69` (`genomes` は起動時 1 回だけ `config/genomes.yml` を読む), `lib/services/service_monitor.rb:20-21`, `lib/services/target_genes_tsv.rb:99-101`, `lib/services/bed_extension_resolver.rb:42`
- **内容**: `rake metadata:load` 後も Puma ワーカーの `/api/search` (空クエリ) の `total` は旧件数のまま、`/api/genome_index` は最大 1 時間旧値、`config/genomes.yml` を編集しても反映されない。全て「更新後に Puma を再起動する」で解決するが、その一文がどこにも無い (RB-02/04)。2 ワーカーが別々のタイミングで TTL 切れになるので、同じページを再読込すると件数が行き来して見えることもある。
- **推奨対策**: 更新手順に再起動を明記する。`total_count_cache` は `INDEX_CACHE_TTL` と同様の TTL を付ける。あるいは `schema_info` 相当の「ロード世代」テーブルを置き、世代が変わったらキャッシュを破棄する。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-10 Gemfile に制約無し、`BUNDLED WITH 2.5.3` の食い違い、`sqlite3` ネイティブ gem は Ruby < 4.1 限定
- **リスク度**: 中
- **顕在化時期**: 数年 (Ruby 4.0 の保守終了 2029 年頃、Debian 13 のアーカイブ化 2030 年頃)、または誰かが `bundle update` した時
- **場所**: `Gemfile:1-24` (全 gem 無制約), `Gemfile.lock:44-51` (`sqlite3 2.9.1` はプラットフォーム別バイナリのみ、`ruby` プラットフォーム無し), `:81-82` (`BUNDLED WITH 2.5.3`), `Dockerfile:1` / `script/dev/build-test-image.sh:9` / `.github/workflows/ci.yml:18` (`4.0.5` 固定), `.ruby-version` (4.0.5)
- **内容**: コンテナで確認: Ruby 4.0.5 同梱 Bundler は 4.0.10 だが、lock の指定により Bundler 2.5.3 が自動導入されて使われ、`bundle exec` のたびに `warning: already initialized constant Gem::Platform::JAVA` 等 16 行の警告 (本番では `puma.stderr.log` へ)。`sqlite3 2.9.1` の `required_ruby_version` は `>= 3.2, < 4.1.dev` で、Ruby を 4.1 に上げた瞬間 `bundle install` が失敗する (ソースビルドの `ruby` プラットフォームも lock に無い)。Gemfile に `~>` が無いため、将来の `bundle update` は Sinatra 5 / Sequel 6 / Puma 8 へ一気に跳ぶ。基盤の `ruby:4.0.5-slim` は Debian 13 trixie で、EOL 後は `apt-get update` が失敗しイメージを再ビルドできない。いずれも「10 年」内に少なくとも 2 回は人手の更新を要する。
- **推奨対策**: Gemfile に `ruby '~> 4.0'` と各 gem の `~>` 制約を書く。`bundle update --bundler` で `BUNDLED WITH` を 4.0.x に揃える。`bundle lock --add-platform ruby`。年次で「Ruby パッチ更新 + `bundle update --conservative` + テスト」を行う旨を README に書く。
- **確認状況**: `ローカルで再現` (gem メタデータ、警告)、`ソース/設定で確認済み`。

### LONG-RB-11 CI は `rackup` (Gemfile 未宣言) で起動確認するため失敗する。sengu ブランチでは CI が一度も走っていない
- **リスク度**: 中
- **顕在化時期**: master へマージした時 / 次に CI が動いた時
- **場所**: `.github/workflows/ci.yml:3-7` (トリガは master への push/PR のみ), `:60` (`bundle exec rackup -p 9292 -D -P tmp/rackup.pid`), `Gemfile` (Rack 3 では `rackup` は別 gem で、lock に無い)
- **内容**: コンテナで `bundle exec rackup --version` → `bundler: command not found: rackup`。CI の "Boot app and verify endpoints" は必ず失敗する。`gh run list` の最終実行は 2026-06-20 の master (dependabot、失敗) で、sengu (master +201 コミット) は未実行。「テスト緑」はローカルの `script/dev/test.sh` のみに依存している。
- **推奨対策**: Gemfile の `:development, :test` に `rackup` を足すか、CI を `bundle exec puma -C config/puma.rb -d` に変える。トリガに `sengu` ブランチ (または全ブランチ) を加える。
- **確認状況**: `ローカルで再現` (rackup 不在)、`ソース/設定で確認済み` (トリガ)。

### LONG-RB-12 相対パス依存と `tmp/pids` の未作成: リポジトリ直下以外からの起動・素のチェックアウトで Puma が起動しない
- **リスク度**: 中
- **顕在化時期**: 初回デプロイ時 / インスタンス入れ替え時 (Docker 以外の経路)
- **場所**: `lib/db.rb:6` (`sqlite://database.sqlite` 相対), `config/puma.rb:27-28,32` (`tmp/pids/puma.pid`, `log/puma.*.log` 相対), `app.rb:64` (`FileUtils.mkdir_p('log')` — `log/` だけ作る), `Dockerfile:6` (`mkdir -p tmp/pids log` はイメージ経路のみ), `puma-7.2.0/lib/puma/launcher.rb:324-331` (`write_pid` は `File.write` のみ), `runner.rb:181-185` (`ensure_output_directory_exists` は無ければ raise)
- **内容**: `tmp/` は `.gitignore` 対象で誰も作らないため、`git clone` 直後に `bundle exec puma -C config/puma.rb` すると pidfile の `Errno::ENOENT` で落ちる (EC2 では unicorn 時代の `tmp/pids` が残っているので偶然動く)。CWD がリポジトリ直下でないと `database.sqlite` を新規作成して「実験 0 件」の空サイトが立つ (エラーにならない)。
- **推奨対策**: `config/puma.rb` 冒頭で `require 'fileutils'; FileUtils.mkdir_p(%w[tmp/pids log])`、`directory File.expand_path('..', __dir__)` を宣言。`lib/db.rb` は `File.expand_path('../database.sqlite', __dir__)` を既定にし、DB ファイルが無ければ起動時に警告する。
- **確認状況**: `ソース/設定で確認済み` (Puma ソース含む)。

### LONG-RB-13 同期の外部 HTTP をリクエストスレッド内で行うため、上流の遅延で 10 スレッドが枯渇しサイト全体が止まる
- **リスク度**: 中
- **顕在化時期**: 特定条件 (NCBI / データサーバ / WABI の遅延)
- **場所**: `config/puma.rb:14-18` (2×5), `routes/pages.rb:37` (/view: NCBI 2 往復、最大 50 s), `routes/api.rb:162-163,196-202` (/api/colo・target_genes: `DataProxy` open 10 s + read 30 s), `lib/services/service_monitor.rb:25-36,69-85` (60 s ごとに 8 s × 最大 3 サービスを **リクエスト内**で実行; ロック無しなので同時到着した複数スレッドが重複プローブ), `routes/jobs.rb:82-87,98-100,111-113` (各ジョブ API が `ServiceMonitor.status` を経由), `lib/services/wabi_service.rb:169` (60 s 既定)
- **内容**: 上流 1 つが応答しなくなると、その機能だけでなくスレッドプール全体が待ちで埋まり、静的ページや `/health` まで nginx の 120 s タイムアウトに達する。`worker_timeout 60` はワーカーのチェックイン監視なので、スレッドが I/O 待ちのままでも再起動されない。
- **推奨対策**: 外部呼出のタイムアウト合計をリクエストあたり 10 s 以内に抑える。`ServiceMonitor` の更新をバックグラウンドスレッド (Puma の `on_worker_boot` で `Thread.new` + sleep 60) に移す。NCBI 取得は非同期 API に (RB-05)。
- **確認状況**: `ソース/設定で確認済み`。

---

## 低

### LONG-RB-14 `lib/db.rb` の PRAGMA (cache_size / mmap_size) は最初の接続にしか効かず、fork 後の Puma ワーカーでは無効
- **リスク度**: 低 (性能のみ)
- **顕在化時期**: 初回デプロイ時から常時
- **場所**: `lib/db.rb:8-12`, `config/puma.rb:36-38` (`before_fork { DB.disconnect }`)
- **内容**: コンテナで確認: PRAGMA 適用後 `DB.disconnect` して新規接続を取ると `cache_size=-2000, mmap_size=0` (`journal_mode=wal` はファイルに永続化されるので残る)。コメントの「64MB cache / 256MB mmap」は本番ワーカーでは効いていない。
- **推奨対策**: `Sequel.connect(url, after_connect: ->(c) { c.execute('PRAGMA cache_size=-64000'); ... })` に移す。
- **確認状況**: `ローカルで再現`。

### LONG-RB-15 `rake db:reset` が FTS5 シャドウテーブルで途中失敗し、DB を空のまま残す (バグ)
- **リスク度**: 低 (開発用タスク)
- **顕在化時期**: 特定条件 (誰かが `rake db:reset` を実行した時)
- **場所**: `Rakefile:17-23`
- **内容**: `DB.tables` は `experiments_fts` とそのシャドウ (`experiments_fts_data` 等 5 表) を両方返す。仮想表を先に drop するとシャドウも消え、次の `drop_table(:experiments_fts_data)` が "no such table" で例外 → `db:migrate` に到達しない。インメモリ DB で再現。
- **推奨対策**: `DB.run("DROP TABLE IF EXISTS experiments_fts")` を先に実行し、残りは `DB.tables.reject { |t| t.to_s.start_with?('experiments_fts') }` を drop する。
- **確認状況**: `ローカルで再現`。

### LONG-RB-16 JSON ボディが配列・文字列・数値のとき 400 ではなく 500 (バグ)
- **リスク度**: 低
- **顕在化時期**: 特定条件 (不正なクライアント / エージェント)
- **場所**: `lib/middleware/json_body_parser.rb:23` (型を問わず `env['parsed_body']` に入れる), `app.rb:49-54`, `routes/jobs.rb:53,127` (`data['type']`, `data['ids']` を Hash/Array 前提で参照), `routes/api.rb:41`
- **内容**: MockRequest で確認: `/jobs/submit` に `[]`・`"str"`・`123` → 500、`/api/igv_url` に `[]` → 500、`/jobs/estimated_time` に `{"ids":"x"}` → 500。いずれも `dump_errors` でバックトレースが stderr ログに残る (RB-03)。
- **推奨対策**: ミドルウェアで `JSON.parse` 結果が Hash でなければ 400 を返す。`total_number_of_reads` は `Array(ids)` で受ける。
- **確認状況**: `ローカルで再現`。

### LONG-RB-17 bedfile 名に `?` を含む 4 件が URL エンコードされず到達不能 (バグ・データ起因)
- **リスク度**: 低
- **顕在化時期**: 特定条件 (該当 4 ファイル)
- **場所**: `lib/services/location_service.rb:80-86` (`filename` を生で連結), `lib/services/bed_extension_resolver.rb:83` (同じ URL を HEAD)
- **内容**: `hg38` の `ATC.PSC.{05,10,20,50}.AllAg.iPSC_derived_erythroid_cells?` (sqlite3 で確認) は `?` 以降がクエリ文字列として扱われ、プローブは両拡張子とも失敗 → 推定 `.bed` で返す URL も 404。ユーザには IGV/ダウンロードが「ファイルが無い」に見える。
- **推奨対策**: `URI::DEFAULT_PARSER.escape` 相当でパスセグメントをエンコードする (`encoded_track` と同様)。上流のファイル名から `?` を除くのが本筋。
- **確認状況**: `ソース/設定で確認済み` + sqlite3 で該当行確認。URL の 404 は `推定` (本番へ叩いていない)。

### LONG-RB-18 `/view` の不正 ID は `redirect '/not_found', 404` でリダイレクトされない (実害無し・可読性)
- **リスク度**: 低
- **顕在化時期**: 常時
- **場所**: `routes/pages.rb:34`, `:152-164` (not_found ハンドラ)
- **内容**: 404 ステータスに Location ヘッダが付くだけで、ブラウザは追随しない。結果的に `not_found` ハンドラが HTML を描くので見た目は正しいが、意図が読めない。MockRequest で `404 location=/not_found` を確認。
- **推奨対策**: `halt 404, erb(:not_found)` に置換。
- **確認状況**: `ローカルで再現`。

### LONG-RB-19 キャッシュのバイト会計が競合で上方ドリフトし、「スレッドセーフでない」コメントが実態と食い違う
- **リスク度**: 低
- **顕在化時期**: 数ヶ月〜数年 (同一キーへの同時ロードの積み重ね)
- **場所**: `lib/services/target_genes_tsv.rb:268-286` (`store`/`evict_until_fits`: 2 スレッドが同じキーを同時に `@cache.delete` → 両方 nil → `@cache_bytes` が 1 エントリ分過大に), `:57-59` と `lib/services/bed_extension_resolver.rb:22-24` (「threaded server で動かすなら lock を」— すでに Puma 5 スレッドで稼働)
- **内容**: `@cache_bytes` は `reset!` (テスト専用) 以外で補正されないため、幻のバイトが積み上がると実キャッシュ 0 でも予算超過扱いになり、毎回全退避 → 実質 1 エントリのキャッシュに退化する。ユーザには見えない (再フェッチ・再パースで遅くなるだけ)。TargetGenes のキー空間は 3,271 (genome,track) × 3 距離 = 9,813、予算 150 MB/プロセス × 2 = 300 MB (推定値ベース; 実測はしていない)。BedExtensionResolver は 112,141 キー中 2,000 件 FIFO で有界。
- **推奨対策**: `Mutex` で `load`/`store` を囲む (1 行) か、`@cache_bytes` を `@cache.sum { |_, e| e[:bytes] }` で都度再計算。コメントを現状に合わせる。
- **確認状況**: `ソース/設定で確認済み` (競合は `推定`)。

### LONG-RB-20 ハードコード定数の棚卸し (変わらない前提なら可、変更時は複数箇所)
- **リスク度**: 低
- **顕在化時期**: 特定条件 (外部側の仕様変更時)
- **場所**: `lib/services/wabi_service.rb:23` (`sbatchOptions '-p epyc -t 180'` — DDBJ の SLURM パーティション名と 180 分上限), `:45-48` (`DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS diffbind:50 / dmr:999`), `routes/jobs.rb:129-130` (`117.13*ln(reads)-2012.5+600`, `1.80e-6*reads+119.38+600` — 2015 年頃の計算機性能に基づく推定式; `Math.log(0)` は `infinite?` で null に落ちるので安全), `lib/models/analysis.rb:7-11` (`TARGET_GENES_DISTANCES 1/5/10` — ファイル名と一致必須), `routes/api.rb:8-11` (`ALLOWED_HOSTS`), `lib/services/{location_service.rb:7, data_proxy.rb:12, bed_extension_resolver.rb:26, service_monitor.rb:14-18, wabi_service.rb:9, sapporo_service.rb:10,58,62, compute_router.rb:81}`, `lib/tasks/metadata.rake:28-29` (ホスト名 `chip-atlas.dbcls.jp` / `dtn1.ddbj.nig.ac.jp` / `ea.chip-atlas.org` が **9 ファイル 16 箇所**に重複), `lib/chip_atlas.rb:22` (`VERSION = '2.0.0'` は未参照; `public/openapi.yaml:5` に別途 `"2.0.0"`), `lib/models/experiment.rb:21-30` (`EXPERIMENT_TYPES` — DB には `No description` 25,689 行・`Unclassified` 38,245 行があり、この一覧に無いため Peak Browser のメニューには出ない。意図的か要確認), `lib/models/experiment.rb:82-86` (`formatted_experiment_count` は千未満切り捨て + 桁区切りで、1,000,000 以上でも "1,000,000" と正しく出る)。ゲノムサイズ / コード遺伝子数テーブルは Ruby 側には無く `frontend/pages/enrichment-analysis.ts:331-360` にある (担当範囲外)。`location_service.rb` に略称マップは存在しない。`SraCache TTL 30 日`、`ServiceMonitor CHECK_INTERVAL 60 s`、`INDEX_CACHE_TTL 1 h`、`TargetGenesTsv TTL 5 min`、`BedExtensionResolver CONFIRMED 1 h / ASSUMED 5 s`。
- **推奨対策**: ホスト名・エンドポイントを `config/endpoints.yml` か `ChipAtlas::Endpoints` 1 箇所に集約。`VERSION` は使うか消す。推定式・SLURM オプションは「変更時はここ」とコメントで明示済みなので現状可。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-21 ジョブ結果ページは `unknown` / 503 で無限ポーリングし、`backend_unavailable` 表示に到達しない (バグ・担当範囲外)
- **リスク度**: 低
- **顕在化時期**: 特定条件 (WABI が status 行の無い 200 を返す、または WABI ダウン)
- **場所**: `routes/jobs.rb:82-90` (503 JSON / `status || 'unknown'`), `frontend/api/client.ts:214-216` (非 2xx で throw), `frontend/components/job-tracker.ts:201-224` (`catch` → `console.warn` → 10 s 後に再ポーリング、上限無し)
- **内容**: Ruby 側が用意した 503 ボディ `{status:'backend_unavailable', retry:false}` はクライアントが例外にするため UI に出ない。`unknown` は FINISHED/FAILED いずれでもないので永久にポーリング。ユーザにはステータス欄が変わらないページが残る。
- **推奨対策**: クライアントで 503 を捕まえて `backend_unavailable` を表示、`unknown` は N 回で打ち切る。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-22 失敗経路のテストが薄い領域
- **リスク度**: 低
- **顕在化時期**: 将来の改修時
- **場所**: `test/**`
- **内容**: 良く書けている領域: TSV パース異常 (502/404 の区別)、ComputeRouter の切替、WabiService の status パース、FTS 整合性、キャッシュ上限。未カバー: `/view` ルート (`test/routes/pages_test.rb:13-16` の PAGES に無い; SraService の NCBI 経路・GSM リダイレクト・404 とも), `SraService` 全体 (テストファイル無し), `ServiceMonitor.check`, `DataProxy.fetch_live` の rescue 集合, `/jobs/estimated_time`, `Bedfile.load_from_file` / `Bedsize.load_from_file`, `metadata.rake` / `clean_old_genomes.rake`, `JsonBodyParser` の非オブジェクト JSON, `formatted_experiment_count`, 本番 `host_authorization`, Puma クラスタモード (ローカルは `WEB_CONCURRENCY=0`)。`bash script/dev/test.sh` は Docker イメージ `chip-atlas-test:local` を先に `build-test-image.sh` で作る前提で、クリーンチェックアウトから 2 コマンドで動く。`rake` は `lib/db.rb` を require するので `rake -T` だけで空の `database.sqlite` を作る副作用がある。
- **推奨対策**: `/view` の 3 経路 (キャッシュヒット / NCBI 失敗スタブ / GSM) と JSON 型ガードのテストを追加。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-23 旧アプリ向けの文書・スクリプト・タスクが残り、将来の保守者を誤導する
- **リスク度**: 低
- **顕在化時期**: 数年 (引き継ぎ時)
- **場所**: `docs/setup.md` (Ruby 2.5.1 / unicorn / `rbenv`), `script/systemctl/*` (unicorn), `script/maintenance/smoke_test.sh:93-128` (旧 `/data/*`, `/wabi_chipatlas`, `/browse` を叩く), `lib/tasks/clean_old_genomes.rake` (hg19/mm9/dm3/ce10 は DB に既に無く、`metadata:load` が genomes.yml で除外するため不要; 呼ばれると `experiments_fts` を全件読み直して再投入する重い処理), コード中の「task A2/A3/B5/C3/D12/F2 の report」参照 (`docs/` にそれらのファイルは無い — `docs/superpowers/` 配下にも該当名無し), `lib/models/experiment_search.rb:67` (「~432k rows」は現在 453,932)。
- **推奨対策**: docs/setup.md を Puma/Docker 手順に書き換え、旧スクリプトは削除か `legacy/` へ。コメントの外部参照は具体的なファイル名か削除に。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-24 `sra_cache` の掃除が呼ばれず、削除された実験の行も残る (実害小)
- **リスク度**: 低
- **顕在化時期**: 数年
- **場所**: `lib/models/sra_cache.rb:37-40` (`clear_expired` はテストからのみ呼ばれる), `lib/tasks/metadata.rake` (`sra_cache` は再ロード対象外)
- **内容**: 行数は実験 ID 数 (454,476) で有界、1 行 1 KB 弱なので最大でも数百 MB。期限切れ行は `get` が nil を返して上書きされるので機能上の問題は無い。
- **推奨対策**: `metadata:load` の末尾で `SraCache.clear_expired` を呼ぶ。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-25 ServiceMonitor の up 判定は「5xx 以外なら up」
- **リスク度**: 低
- **顕在化時期**: 特定条件 (WABI/WES のパス廃止・移転)
- **場所**: `lib/services/service_monitor.rb:79-80` (`response.code.to_i < 500`)
- **内容**: WABI は HEAD に 405 を返すので 405 を「up」と読んでいる (偶然動作)。パスが 404 になっても 'ok' のまま投入に進み、`submission_rejected` (502) で初めて分かる。外部不変の前提では問題にならない。
- **推奨対策**: WABI は `GET ?info=status` 相当の軽い GET にし、200 のみ up とする。
- **確認状況**: `ソース/設定で確認済み`。

### LONG-RB-26 qval コードの文字列ソートと fileList.tab の可変列数
- **リスク度**: 低
- **顕在化時期**: 特定条件 (新しい閾値コードの追加時)
- **場所**: `lib/models/bedfile.rb:38-46` (`select_map(:qval).sort` は文字列ソート; 現在 `05,10,20,50` + 除外される `anno,bs`), `:56-71` (fileList.tab は 7〜8 列で `cols[7]` が nil の行あり — `experiments` 列 NULL として保存、参照箇所無し)
- **内容**: `'100'` のようなコードが増えると `05,10,100,20,50` の順になる。現状は問題なし。
- **推奨対策**: `sort_by(&:to_i)`。
- **確認状況**: `ソース/設定で確認済み` (sqlite3 で qval 一覧確認)。

---

## 問題なしと確認した項目

- **Ruby/gem API**: `Time#iso8601` は `sinatra/base` が `time` を読み込むため利用可 (コンテナで確認)。Logger の formatter proc (4 引数)、`Net::HTTP#get/head/request_head`、`Net::HTTP.post_form`、`URI.parse`、`URI.encode_www_form_component`、`Hash#compact/#except`、`String#each_line(chomp:)`、`Comparable#clamp` はいずれも Ruby 4.0.5 で有効。`Timeout.timeout` で Net::HTTP を包む箇所 (`service_monitor.rb:73`) は内側にも個別タイムアウトがあり安全。`require 'set'` は Ruby 4.0 でも無害。`csv`/`ostruct`/`mutex_m`/`observer` 等の bundled gem 化された標準ライブラリは未使用。`logger`/`base64`/`bigdecimal`/`drb` は lock に含まれる。`rexml` は Gemfile で宣言済み。
- **Rack 3 / Sinatra 4**: `JsonBodyParser` のヘッダは小文字 (`'content-type'`)。`response.content_type&.start_with?` (`routes/pages.rb:153`) は Sinatra 4 で動作 (テスト `pages_test.rb:345` で確認)。`cache_control`, `attachment`, `halt` の用法に問題なし。`Rack::Protection::HttpOrigin` はクロスサイト form POST (`/enrichment_analysis`) を拒否しない (MockRequest で 200 を確認)。
- **Sequel / SQLite**: `insert_conflict` (UPSERT) は SQLite ≥ 3.24、`COUNT(*) OVER()` は ≥ 3.25、FTS5 有効 — コンテナの SQLite は 3.51.2。`Sequel.extension :migration` の用法正常。マイグレーションは 3 まで適用済み (`schema_info = 3`)。接続プール 4 / スレッド 5 だが接続はクエリ単位で返却されるので実用上枯渇しない。busy_timeout 既定 5 s。Logger の日次ローテーションは `flock` でプロセス間排他している (`log_device.rb:177-182`) ので 2 ワーカーでも壊れない。
- **FTS5 クエリの堅牢性**: `fts5_sanitize` により `-`, `"`, `a:b`, `NOT`, `AND`, `OR`, `\`, `“x”`, `*`, `(`, `%`, `_`, `st*at`, `NEAR(a,b)`, `+`, `x|y`, 日本語 の 21 種が全て 200 (0 件または妥当な件数)。2,000 トークンの URL は 400 (リクエスト行上限) で 500 にならない。`offset=-5` / `offset=1e9` / `limit=abc` も 200。
- **データ形状 (2026-09-13 スナップショット実測)**: experimentList.tab 867,660 行に不正 UTF-8 0 行、9 列未満 0 行。fileList.tab 212,230 行、不正 0 行、列数 7〜8。DB: experiments 454,476 行 = distinct experiment_id 454,476 (重複 (id,genome) 0)、`read_info` は全行 `数値,` 形式 (総リード 0 の 544 行は Annotation tracks)、track 名・cell_type_class に URL 特殊文字・カンマ無し、analyses 7 ゲノム全て genomes.yml と一致。`Math.log(0)` → `-Infinity` は `infinite?` で `minutes: null` に落ち、フロントは `—` を表示 (MockRequest で確認)。`Rational(seconds, 60)` は Float を受け付ける。
- **キャッシュの有界性**: `BedExtensionResolver` 2,000 件 FIFO、`TargetGenesTsv` 150 MB/プロセス (推定値)、`ColoTsv` は無キャッシュ、`Experiment.cached_index_all_genome` は 1 ハッシュ。TSV サービスに負の (404 の) キャッシュは無く、`BedExtensionResolver` の未確認結果は 5 s で再試行される。
- **`formatted_experiment_count`**: `(count/1000)*1000` + 桁区切り正規表現で、1,000,000 以上でも "1,000,000" 形式で崩れない。
- **ローダのトランザクション**: INSERT 側は 4 ローダとも `DB.transaction` 内で 5,000 行バッチ (DELETE の位置は RB-02)。`metadata:load` 後の `assert_no_orphaned_fts_rows!` と broken-build 検知は良い仕組み。
- **Puma 設定**: `preload_app!` + `before_fork { DB.disconnect }` の組合せは正しい。`worker_timeout 60` は暴走ワーカーの自己回復に働く。`redirect_io` より前にアプリが preload されるため `app.rb:64` の `mkdir_p('log')` は間に合う。
- **`.dockerignore`** は存在する (316 B)。

## 未確認・不確実事項

- ALB のヘルスチェック設定 (パス・ポート・プロトコル・成功コード) は AWS 側にあり、リポジトリからは読めない。RB-01 は「Host ヘッダがターゲット IP になる」という AWS の一般仕様に基づく推定で、実際にデプロイして確認する必要がある。
- `script/deploy/deploy.sh` が旧アプリで一度でも成功したか (nginx :80 の 301 と `curl http://IP/health` の組合せは旧アプリでも通らないように見える) は履歴から判断できなかった。
- Puma クラスタモード (2 ワーカー) はローカルコンテナが `WEB_CONCURRENCY=0` / `RACK_ENV=development` で動いているため一度も実行していない。`preload_app!`/`before_fork` 経路、ワーカー間のキャッシュ不整合 (RB-09) は未検証。
- 本番のリクエスト量・ディスク容量・インスタンスサイズが不明のため、RB-03/06 の増加速度は外挿。`TargetGenesTsv` の実メモリ (推定式 40+8×列 バイト/行) は実測していない。
- NCBI E-utilities のレート制限 (API キー無しで 3 req/s) がクローラ負荷で実際に 429 を出す頻度、CA バンドルの劣化時期 (RB-05/07) は推定。
- `EXPERIMENT_TYPES` に無い `No description` / `Unclassified` (計 63,934 行) を Peak Browser から除外しているのが意図か (新旧比較担当の範囲)。
- `sengu` ブランチで GitHub Actions が動いていないため、CI 定義全体 (iptables による遮断、`npm ci`、nginx 構文検証) が現在の Ubuntu ランナーで通るかは未確認。
- `rake metadata:load` の DB 書込みを伴う実行は行っていないため、総所要時間と WAL ファイルの最大サイズ (推定 600 MB 超) は未計測。
