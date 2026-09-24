# LONG-OPS: 10 年メンテナンスフリー観点 — ランタイム / 運用 (2026-09-23)

## 担当範囲の要約と総評

担当: プロセスのライフサイクル、デプロイ、ディスク・ログ・DB の成長、OS/ランタイムの陳腐化、再起動・インスタンス入れ替え耐性、証明書、監視、データ更新手順。
対象: `config/puma.rb`, `config/nginx/chip-atlas.conf`, `app.rb`, `lib/db.rb`, `lib/models/*`, `lib/services/*`, `Dockerfile`, `docker-compose*.yml`, `.github/workflows/*`, `script/deploy`, `script/launch-instance`, `script/systemctl`, `docs/setup.md`, `README.md`, `Rakefile` + `lib/tasks/*.rake`。インストール済み gem (sinatra 4.2.1 / rack-protection 4.2.1 / puma 7.2.0 / sequel 5.103.0 / logger 1.7.0) のソースは `docker exec chip-atlas-local` で読んだ。

総評:
1. **アプリ本体 (Ruby プロセス) は、動き続ける限り 10 年もつ設計にほぼなっている**。プロセス内キャッシュは有界 (BedExtensionResolver 2000 件、TargetGenesTsv 150MB 予算、ColoTsv はキャッシュ無し)、SQLite の書き込みは `sra_cache` だけで WAL も肥大しない、日付・年のハードコードや 2038 年問題は無い。
2. **一方で「動かす・動かし続ける・入れ替える」ための運用層が新版に存在しない**。`script/deploy/deploy.sh` は `origin/master` (旧版) を checkout し、存在しない `rake pj:load_metadata` を呼び、Gemfile に無い `unicorn` を起動する。Puma を起動する systemd unit も init script も無く、`script/systemctl/chip-atlas` は rbenv + unicorn の SysV script。つまり**新版は初回デプロイの時点で人手が要り、再起動・クラッシュから自力で復帰する仕組みが無い**。
3. リポジトリの nginx 設定 (80→301、443 + Let's Encrypt) は本番トポロジ (ALB が ACM 証明書で TLS 終端し、インスタンスの nginx は 80 番を素で応答) と矛盾しており、そのまま配置するとリダイレクトループかヘルスチェック失敗になる。
4. 時間経過で確実に効いてくるのは、(a) `Logger 'daily'` が古いファイルを消さないこと + Puma のログが追記のみでローテーション無し、(b) `metadata/<timestamp>/` が 1 回 660MB ずつ蓄積すること、(c) 本番 OS (nginx 1.18.0 = Ubuntu 20.04/22.04) の EOL で `deploy.sh` の `apt-get update` が失敗すること。
5. 今回のレビュー中にローカル新版が実際に SIGBUS (sqlite3 + `PRAGMA mmap_size`) で落ち、誰も再起動しなかった (2026-09-23T14:18:13Z、`/api/search` 処理中)。私が `docker start` で復旧させた。「クラッシュ→自動復帰」が無いことの実証になった。
6. 監視・アラート・DB バックアップは repo に一切無い。DB はメタデータから再生成できるので backup 不要という設計判断自体は妥当だが、文書化されていない。

以下、リスク順。

---

### <LONG-OPS-01> 新版のデプロイ経路が存在しない (deploy.sh は旧版・旧構成専用)
- **リスク度**: 高
- **顕在化時期**: 初回デプロイ時 (GitHub Actions `Deploy` を実行した瞬間)
- **場所**: `script/deploy/deploy.sh:232-261`, `.github/workflows/deploy.yml:51-60`, `Rakefile:10-26`, `lib/tasks/metadata.rake:70`, `Gemfile`
- **内容**: プロビジョニング手順 (`deploy.sh:229-265`) は
  - `git reset --hard origin/master` (:235) — **sengu ブランチではなく旧版 master を配置する**。
  - `bundle exec rake pj:load_metadata` (:254) — 新版に `pj:` namespace は無い (`docker exec chip-atlas-local bundle exec rake -P` で確認: 存在するのは `metadata:load{,_experiment,_bedfile,_analysis,_bedsize}` と `db:{migrate,reset,clean_old_genomes}` のみ)。旧版 `old-app/Rakefile:14-16` には `pj:load_metadata` があるので、これは旧版用の記述。`set -euo pipefail` (:10) により rake が abort した時点でデプロイ全体が失敗する。
  - `bundle exec unicorn -c unicorn.rb -D` (:260) — `unicorn` は Gemfile.lock に無く、`unicorn.rb` は commit `3bb539b` で削除済み。Puma を起動するコマンド (`bundle exec puma -C config/puma.rb`) はどこにも無い。
  - `bundle install --deployment` (:238) は AMI 上の rbenv に Ruby 4.0.5 (`.ruby-version`) が入っていることを前提とするが、旧版 AMI は Ruby 3.2.2 (`old-app/.ruby-version`)。AMI の作り直し手順は repo に無い。
  - `npm ci && npm run build` に相当する手順が無い (後述 LONG-OPS-13)。
  - デプロイ対象 AMI は「アカウント内で最も新しい `sapporo` 以外の AMI」(:139-143) で、名前も用途も検証しない。
  運用者から見ると: `Deploy` ワークフローは Step 5 で必ず失敗する。仮に 3 箇所を直しても、Ruby 4.0.5 入りの AMI と Node ビルド成果物が無ければ動かない。
  なお設計文書も一貫していない: `SHIKINEN-SENGU.md:851` は "Docker + Unicorn + NGINX"、`docs/superpowers/specs/2026-04-04-shikinen-sengu-design.md:1066` は "Docker + Puma + NGINX"、実際の `deploy.sh` は Docker を使わない bare-metal 配置。
- **推奨対策**: デプロイ方式を 1 つに決めて repo に閉じる。最小案: (1) `deploy.sh` を `origin/sengu` (マージ後は master) に向け、`rake metadata:load` に直し、Puma 起動を systemd 経由 (`sudo systemctl restart chip-atlas`) にする。(2) AMI 依存を無くすため cloud-init / user-data で Ruby 4.0.5 (公式 ruby イメージを使う Docker 化が最も再現性が高い: `Dockerfile` は既にある) と nginx を入れる。(3) `npm ci && NODE_ENV=production npm run build` を CI で行い、成果物を deploy に同梱する。(4) `--dry-run` だけでなく実際に一度通した deploy ログを `docs/` に残す。
- **確認状況**: `ソース/設定で確認済み` (rake タスク一覧はローカル docker で確認)

### <LONG-OPS-02> Puma を起動・再起動・監視する仕組みが無い (再起動/クラッシュで停止したまま)
- **リスク度**: 高
- **顕在化時期**: 初回再起動時 / 初回クラッシュ時 (AWS の予定メンテナンスによる再起動は年単位で必ず来る)
- **場所**: `script/systemctl/chip-atlas:13-23`, `script/systemctl/README.md`, `config/puma.rb:27-28`, `docker-compose.yml:1-9`, `Dockerfile:7`
- **内容**:
  - 唯一の起動スクリプト `script/systemctl/chip-atlas` は SysV init で、`PATH=~/.rbenv/...; bundle exe unicorn -c unicorn.rb -E production -D` (:18) を実行する。新版では unicorn も unicorn.rb も無いので、これが AMI の `/etc/init.d/` に入っていても再起動後にアプリは上がらない (nginx だけが上がり 502 を返す → ALB が unhealthy と判定 → サイト停止)。
  - Puma 用の systemd unit は repo のどこにも無い (`grep -rniI systemd\|systemctl` の該当は deploy.sh の `systemctl reload nginx` のみ)。
  - `docker-compose.yml` には `restart:` ポリシーが無く、`volumes:` も無い (イメージは `.dockerignore:4` で `database.sqlite` を除外しているので、そのまま起動すると空 DB で立ち上がる)。ホスト再起動後にコンテナは戻らない。
  - Puma cluster mode (`workers 2`) は worker の死亡は master が再 fork するが、master 自身の死亡や single mode (`WEB_CONCURRENCY=0`、ローカルと同じ) の死亡は誰も面倒を見ない。
  - **実証**: 2026-09-23T14:18:13Z、ローカルの新版 (single mode) が `sqlite3-2.9.1 resultset.rb:43: [BUG] Bus Error` で異常終了し (`docker logs` 行 1330-2567、Ruby レベルのバックトレースは `routes/api.rb:100` → `lib/models/experiment_search.rb:117`、つまり別エージェントの `/api/search?q=...` 処理中)、コンテナは `Exited (133)` のまま約 2〜3 分間放置された (私の `/api/search` への curl が `000` になって気付き、`docker start chip-atlas-local` で復旧した)。本番で同じことが起きれば、人が気付くまで停止する。
- **推奨対策**: `config/systemd/chip-atlas.service` を repo に追加し deploy で配置する。要点: `WorkingDirectory=/home/ubuntu/chip-atlas` (app.rb:64-65 の `log/`、puma.rb:27 の `tmp/pids/`、lib/db.rb:6 の `sqlite://database.sqlite` は全て CWD 相対)、`Environment=RACK_ENV=production`、`ExecStart=.../bundle exec puma -C config/puma.rb`、`Restart=always`、`RestartSec=5`、`KillMode=mixed`、`WantedBy=multi-user.target`。Docker 運用なら `restart: unless-stopped` と DB のボリュームを `docker-compose.yml` に書く。`script/systemctl/` は削除する (誤って使われるだけ)。
- **確認状況**: `ソース/設定で確認済み` + `ローカルで再現` (クラッシュ後に再起動されないこと)

### <LONG-OPS-03> nginx 設定が本番トポロジ (ALB + ACM) と矛盾: 配置すると `nginx -t` 失敗かリダイレクトループ
- **リスク度**: 高
- **顕在化時期**: 初回デプロイ時 (`deploy.sh:244-248` が config を上書きして `nginx -t && systemctl reload nginx` する)
- **場所**: `config/nginx/chip-atlas.conf:5-9` (80→301), `:11-19` (443 + `/etc/letsencrypt/live/chip-atlas.org/*`), `:55-65` (`/health`), `script/deploy/deploy.sh:244-248`
- **内容**: 本番の実測 (軽量 GET):
  - `curl -I http://chip-atlas.org/` → `200 OK`, `Server: nginx/1.18.0 (Ubuntu)`。**リダイレクトされない**。つまり ALB の HTTP リスナがインスタンスの 80 番へそのまま転送し、インスタンス側 nginx は旧版 `old-app/config/nginx/chip-atlas.conf` (listen 80 のみ、`server_name _`) 相当で動いている。
  - `curl -svI https://chip-atlas.org/` → 証明書 `CN=chip-atlas.org`, **issuer `Amazon RSA 2048 M01`**, 有効期間 2025-12-04 〜 2027-01-02。**TLS 終端は ALB (ACM 証明書)** であり、Let's Encrypt はどこにも使われていない。
  新版の設定を配置すると:
  - `/etc/letsencrypt/live/chip-atlas.org/fullchain.pem` が AMI に無ければ `nginx -t` が失敗し、`set -e` でデプロイ中断 (nginx は reload されないので旧設定のまま動き続ける)。
  - もし証明書ファイルがあれば、80 番は全パス 301 → ALB が 80 番へ転送する限り `https://chip-atlas.org/` → 301 `https://chip-atlas.org/` の**無限リダイレクト**、ALB ヘルスチェックも 301 (matcher が 200 なら unhealthy)。`/health` は 443 側にしか無い (:55-65)。
  - certbot / 更新 cron / systemd timer は repo に一切無い。仮に Let's Encrypt で運用するなら 90 日で失効するが、現状は ACM なので**証明書の失効リスク自体は無い** (ACM は自動更新。DNS 検証レコードが残っている前提: 未確認)。
- **推奨対策**: 本番トポロジに合わせて `listen 80` の単一 server ブロックに戻す (旧版 conf を Puma 向けに `upstream 127.0.0.1:9292` に変えただけのもの)。HTTPS 強制は ALB のリスナルール (HTTP→HTTPS redirect) で行い、nginx は `X-Forwarded-Proto` を見るだけにする。443/Let's Encrypt を残すなら、`deploy.sh` で証明書の存在を検査してから配置し、certbot の systemd timer と webroot (`/home/ubuntu/chip-atlas/public/.well-known`) 設定を repo に入れる。どちらの構成かを `docs/` に 1 枚で書く。
- **確認状況**: `ソース/設定で確認済み` (本番の応答ヘッダ・証明書は curl で確認)

### <LONG-OPS-04> `/health` は Host が IP だと 403 → deploy.sh のヘルス待ちは絶対に通らない (ALB ヘルスチェックも同じ条件)
- **リスク度**: 高
- **顕在化時期**: 初回デプロイ時 (Step 6 で 300 秒待って `die`)
- **場所**: `app.rb:70-72` (`permitted_hosts: ['.chip-atlas.org']`), `config/nginx/chip-atlas.conf:58` (`proxy_set_header Host $host`), `script/deploy/deploy.sh:283-287` (`http://$NEW_INSTANCE_IP/health` の 200 を要求), gem: `rack-protection-4.2.1/lib/rack/protection/host_authorization.rb:55-80`, `sinatra-4.2.1/lib/sinatra/base.rb:1878-1880, 1980-1993`
- **内容**: Sinatra 4.2.1 は `host_authorization` 設定を `Rack::Protection::HostAuthorization` に渡す (base.rb:1879)。`accepts?` (host_authorization.rb:55-80) は `allow_if` が無い限り `Host` (と `X-Forwarded-Host`) を `permitted_hosts` と照合し、不一致なら `default_reaction :deny` (:29) = 403 "Host not permitted"。ローカル docker は `RACK_ENV=development` なので、`docker exec -e RACK_ENV=production` で `Rack::MockRequest` を使い production 設定で検証した:
  - `Host: 10.0.0.1` / `10.0.0.1:80` / `172.30.2.171:9292` / `localhost` / `evil.com` → **403 "Host not permitted"**
  - `Host: chip-atlas.org` / `www.chip-atlas.org` / `foo.chip-atlas.org` → 200
  - `Host: chip-atlas.org` + `X-Forwarded-Host: 10.0.0.1` → 403
  本番旧版も同じ設定 (`old-app/app.rb:88`) で、`curl -H 'Host: 10.0.0.1' https://chip-atlas.org/health` → **403 "Host not permitted"** を実測した。
  結果:
  - `deploy.sh:284-285` は IP 直打ちなので Host は IP → (nginx が 301 を返さない構成でも) 403 → 200 待ちがタイムアウトして必ず `die`。`script/launch-instance/launch-chip-atlas.sh:68,75` は「200 または 403 を成功扱い」と、この挙動を織り込んでいるのに `deploy.sh` は織り込んでいない。
  - ALB のヘルスチェックは Host ヘッダをターゲット IP にして送る (AWS 仕様、推定) ので、`/health` を叩く設定なら本番でも 403 のはず。本番が healthy として動いている以上、ALB 側は matcher に 403 を含めているか、`/health` 以外 (nginx が直接返す静的ファイル等) を見ている (未確認)。前者なら「アプリが誤設定で 403 を返していても healthy」という穴になる。
- **推奨対策**: nginx の `location = /health` で `proxy_set_header Host chip-atlas.org;` に固定する (最小変更)。または `app.rb` で `set :host_authorization, { permitted_hosts: ['.chip-atlas.org'], allow_if: ->(env) { env['PATH_INFO'] == '/health' } }` (rack-protection 4.2.1 は `allow_if` をサポート: host_authorization.rb:30,56)。`deploy.sh` の curl に `-H 'Host: chip-atlas.org'` を付ける。ALB target group の health check path / matcher を確認して `docs/` に記録する。
- **確認状況**: `ローカルで再現` (production モードの MockRequest) + 本番旧版で同挙動を確認

### <LONG-OPS-05> OS / ランタイムの EOL で `deploy.sh` と `docker build` が失敗する (日付が決まっている)
- **リスク度**: 高 (時限)
- **顕在化時期**: 特定日付 — 本番 OS: 2027 年 4〜6 月 (Ubuntu 22.04 の場合) / 既に (20.04 の場合)。Docker ベース: 2028〜2030 年 (Debian 13)。Ruby 4.0 系: 2029 年 3 月頃 (推定)
- **場所**: `script/deploy/deploy.sh:240-242` (`sudo apt-get update -qq && apt-get upgrade -y -qq`、`set -e` 配下), `Dockerfile:1-2` (`ruby:4.0.5-slim` = Debian 13 trixie、`apt-get update`), `.ruby-version` (4.0.5), `.github/workflows/ci.yml:16-18`
- **内容**:
  - 本番の `Server: nginx/1.18.0 (Ubuntu)` から、AMI の OS は Ubuntu 20.04 (focal) か 22.04 (jammy) (どちらも nginx 1.18.0 を同梱。24.04 は 1.24.0)。20.04 の標準サポートは 2025-05 で終了済み、22.04 は 2027-04 (推定 2027-06 まで猶予)。EOL 後しばらくするとパッケージが `old-releases.ubuntu.com` に移され `apt-get update` が 404 で非ゼロ終了 → `deploy.sh` Step 5 で中断。以後は AMI 自体を作り直さない限りデプロイ不能。
  - `docker exec chip-atlas-local cat /etc/os-release` → `Debian GNU/Linux 13 (trixie)`。Debian のアーカイブ移行後は `Dockerfile:2` の `apt-get update` が同様に失敗 (`docker build` 不能)。`ruby:4.0.5-slim` タグ自体は残るが、再ビルドできなくなる。
  - Ruby 4.0 系は 2025-12 リリース → 通常 3 年強でセキュリティ保守終了 (2029 年前半、推定)。外部依存不変の前提では「動かなくなる」わけではないが、以後は脆弱性修正が来ない。
  - `ruby/setup-ruby@v1`, `actions/checkout@v4` 等の GitHub Actions は数年おきに Node ランタイム更新で警告→失敗する (GitHub 不変の前提から外れるので参考)。
- **推奨対策**: OS 更新を deploy 手順から切り離す (`apt-get upgrade` を失敗しても継続にするか、unattended-upgrades に任せる)。AMI ではなく最新 Ubuntu LTS の公式 AMI + user-data で構築するか、Docker 化してベースイメージを `ruby:4.0.5-slim-<codename>` のように codename まで固定し、`apt-get update` の失敗を `docker build` の停止条件にしない設計にする。EOL 日付 (Ubuntu 22.04: 2027-04、Debian 13: 2028-08 頃、Ruby 4.0: 2029-03 頃) を `docs/` に「期限付き作業」として書く。
- **確認状況**: nginx バージョンは本番で確認、OS の版は `推定` (20.04 か 22.04 のどちらか)、EOL 日付は `推定`

### <LONG-OPS-06> ログが無限に溜まる: `Logger 'daily'` は古いファイルを消さず、Puma のログは追記のみ、logrotate 無し
- **リスク度**: 中
- **顕在化時期**: 数年 (アクセス量依存。エラー多発時は数ヶ月)
- **場所**: `app.rb:65` (`Logger.new('log/access_log', 'daily')`), `config/puma.rb:32` (`stdout_redirect 'log/puma.stdout.log', 'log/puma.stderr.log', true`), gem: `logger-1.7.0/lib/logger/log_device.rb:162-175, 216-230`
- **内容**:
  - Ruby の `Logger` で `shift_age='daily'` (文字列) を指定した場合、`check_shift_log` (log_device.rb:169-173) は日付が変わった最初の書き込み時に `shift_log_period` を呼び、`shift_log_period` (:216-230) は `File.rename(@filename, "#{@filename}.YYYYMMDD")` するだけで**古いファイルを unlink する経路が無い**。保持世代数を持つのは `shift_age` が整数 (サイズローテーション) の場合の `shift_log_age` (:207-214) だけ。従って `log/access_log.YYYYMMDD` は永久に増える。証拠: `ls log/` に `access_log.20260404` から `access_log.20260922` まで 18 個の日付付きファイル (4 月〜9 月、書き込みのあった日だけ生成されるので飛び飛び)。
  - `puma.stdout.log` / `puma.stderr.log` は append (第 3 引数 `true`) で、ローテーションは無い。stderr には未捕捉例外ごとに 2〜3KB のバックトレースが書かれる (ローカルの `log/puma.stderr.log` は既に 44KB)。スキャナやボットがエラー経路を叩き続けると月あたり数十 MB〜。
  - Puma 7.2.0 は `stdout_redirect` 設定時に SIGHUP でログを reopen する (`puma/launcher.rb:467-472`) ので logrotate と組み合わせられるが、その logrotate 設定は repo に無い。nginx のアクセスログは Ubuntu パッケージ同梱の `/etc/logrotate.d/nginx` (daily, 14 世代) が効く (推定)。
  - 1 行あたり access_log は ~100B。ボット込みで 1 日 10 万リクエストなら 10MB/日 → 10 年で 36GB。t3.medium のルート EBS サイズは repo からは分からない (`BlockDeviceMappings` は launch template 側)。
- **推奨対策**: (1) `app.rb:65` を `Logger.new('log/access_log', 30, 50 * 1024 * 1024)` (30 世代 × 50MB) にするか、`'daily'` を続けるなら `/etc/logrotate.d/chip-atlas` を repo に置き `log/access_log.*` を `maxage 90` で削除する。(2) Puma のログは同じ logrotate で `postrotate systemctl kill -s HUP chip-atlas` (または journald に流し `SystemMaxUse=` で上限)。(3) ディスク使用率のアラーム (CloudWatch `disk_used_percent` > 80%) を 1 本入れる。
- **確認状況**: `ソース/設定で確認済み` (logger gem のソースと `ls log/` の実物)

### <LONG-OPS-07> `metadata/<timestamp>/` が更新のたびに ~660MB ずつ蓄積し、削除する仕組みが無い
- **リスク度**: 中
- **顕在化時期**: 数回の更新で GB 級 (ローカルは既に 6 ディレクトリ 1.5GB)
- **場所**: `lib/tasks/metadata.rake:19-21` (`Time.now.strftime('%Y%m%d-%H%M')` ごとに新ディレクトリ), `:31-68` (`file` タスクは新ディレクトリに再ダウンロード)
- **内容**: `rake metadata:load` を実行するたびに `metadata/YYYYMMDD-HHMM/` が作られ、`experimentList.tab` 353MB + `ExperimentList_adv.json` 171MB + `fileList.tab` 139MB + 小物 = **約 660MB** が落ちてくる (`du -sh metadata/*`: 459M, 329M, 131M, 660M ...)。ロード後にディレクトリを消す処理は無く、`.gitignore:8` で無視されているので誰の目にも触れない。ローカルには rake の部分実行で分割されたディレクトリも含め 6 個/1.5GB が残っている。同じ理由で `database.sqlite`, `.latest`, `.rebuild`, `.verify` (各 ~650MB、計 2.5GB) がリポジトリ直下に並んでおり、本番でも同じ作業をすれば同じ状態になる。
  さらにロード中は 1 トランザクションで 45 万行を書くため WAL が DB サイズ級 (数百 MB) まで膨らみ、一時的に DB の 2 倍のディスクを使う (SQLite の仕様、推定)。
- **推奨対策**: `metadata:load` の最後 (成功時) に `metadata_dir` を削除するか、`metadata/latest` シンボリックリンク方式にして N 世代だけ残す。DB のコピーは作業ディレクトリ外 (`/var/lib/chip-atlas/` 等) に置く運用にし、`docs/` に書く。ディスクアラームは LONG-OPS-06 と共通。
- **確認状況**: `ソース/設定で確認済み` + ローカルの実物

### <LONG-OPS-08> メタデータ更新がどこにもスケジュールされておらず、稼働中 DB に対して実行すると数分間サイトが「空」になり、プロセス内キャッシュも再起動まで古いまま
- **リスク度**: 中
- **顕在化時期**: 初回デプロイ以降ずっと (データは deploy 時点で凍結) / 更新を稼働中に実行した時
- **場所**: `lib/tasks/metadata.rake:86-99` (`:89-90` `DB[:experiments].delete` / `DB[:experiments_fts].delete` がトランザクションの外), `:104`, `:112`, `:131` (同様), `lib/models/experiment.rb:290` (トランザクションは insert 部分のみ), `lib/models/experiment_search.rb:72-87` (`total_count_cache`), `lib/models/experiment.rb:32-34,107-116` (`@index_cache` 1h)
- **内容**:
  - cron / systemd timer / GitHub Actions schedule は repo に無い。`deploy.sh` が呼ぶ `rake pj:load_metadata` は存在しない (LONG-OPS-01)。つまり**新規実験は、人が `rake metadata:load` を走らせて Puma を再起動しない限り 10 年間増えない**。トップページの「N experiments」も凍結する。silent (エラーにはならない)。
  - `metadata:load_experiment` は `DB[:experiments].delete` (:89) を**トランザクション外で即コミット**し、その後 `load_from_files` が `DB.transaction` (experiment.rb:290) で挿入する。WAL の読み手はコミット済み状態を見るので、稼働中 DB に対して実行すると**削除〜挿入コミットまでの数分間、`/view` は全て 404、Peak Browser の件数は 0、`/health` は `experiments: 'empty'`** になる。`bedfiles` (:104)、`analyses` (:112)、`bedsizes` (:131) も同じ形。`deploy.sh --skip-launch` (稼働中インスタンスの再プロビジョニング) はまさにこの経路。
  - ロード後、rake プロセスは `reset_total_count_cache!` (experiment.rb:404) を呼ぶが、それは rake プロセス内の話。Puma worker の `ExperimentSearch.total_count_cache` は無期限 (experiment_search.rb:82 `||=`) なので、再起動するまで検索の `total` が古い値のまま。`Experiment.@index_cache` は 1 時間 (:34) で追随する。
  - `metadata.rake:6-16` の `download_file` は 353MB を `response.body` でメモリに全部載せてから `File.write` (:15) する。t3.medium (4GB) では動くが、Puma 2 worker と同居して実行すると瞬間的に厳しい。リトライも無い。
  - `load_analysis` (:115-125) は「壊れたビルド (`.1/.5/.10` サフィックス)」を検出しても warn するだけで続行する (設計意図どおりだが、無人運用では誰も warn を読まない)。上流ファイルの列構造が変わった場合: `experimentList.tab` の列ずれは `genomes.key?(genome)` (experiment.rb:306) で行が全部捨てられ **0 件ロードで正常終了** (silent)、`ExperimentList_adv.json` の構造変化は `JSON.parse(...)['data']` (:415) が nil なら `|| []` で空 → FTS 0 件で正常終了 (silent)、`assert_no_orphaned_fts_rows!` (metadata.rake:92) は「FTS にあって experiments に無い」方向しか検査しない。
- **推奨対策**: (1) 更新を「別ファイルに新 DB を作る → 検証 (件数が前回の 90% 以上等) → `mv` で差し替え → Puma を `systemctl restart`」の手順にし、稼働中 DB を in-place で消さない (`DATABASE_URL=sqlite://database.sqlite.new rake db:migrate metadata:load`)。(2) 無人更新をするなら systemd timer で月次実行し、失敗時は前回 DB を維持。(3) ロード後の件数ガード (`experiments` が 0 または前回比で激減なら raise) を `metadata:load` に入れる。(4) `Rakefile` の `metadata:*` に `desc` を付ける (現状 `rake -T` に出ないので運用者が見つけられない)。
- **確認状況**: `ソース/設定で確認済み` (空白窓の発生は SQL の順序からの推論で `推定`)

### <LONG-OPS-09> `PRAGMA mmap_size=256MB` により I/O 異常が例外ではなく SIGBUS/SEGV になり、プロセスごと落ちる (ローカルで発生)
- **リスク度**: 中
- **顕在化時期**: 特定条件 (DB ファイルの truncate/差し替え/VACUUM を稼働中に行った時、EBS の I/O エラー時、mmap が不安定なファイルシステム上)
- **場所**: `lib/db.rb:12` (`PRAGMA mmap_size=268435456`), `lib/tasks/clean_old_genomes.rake:89-92` (`VACUUM`), `config/puma.rb:14` (`workers 2`)
- **内容**: 2026-09-23T14:18:13Z、ローカル新版 (`database.sqlite.verify` を macOS からの bind mount で使用、Puma single mode) が `/api/search` の FTS 検索 (`experiment_search.rb:117`) 実行中に `sqlite3-2.9.1 resultset.rb:43: [BUG] Bus Error at 0x0000ffffbe93d6c6` で異常終了した。SIGBUS は mmap したファイルの領域にアクセスできない時の典型的な信号で、SQLite の mmap ドキュメントも「I/O エラーが SIGBUS/SEGV になりエラーコードでは返らない」と明記している。同じクエリを別プロセスで mmap あり/なしで再実行しても再現しなかった (0.15s / 0.2s、total 19170) ので、Docker Desktop の bind mount (virtiofs) 上での mmap の不安定さが直接原因の可能性が高い (推定)。
  本番 (EBS/ext4) で同型の事故を起こす経路は明確にある: `db:clean_old_genomes` の `VACUUM` (ファイルを縮める) や、稼働中 `database.sqlite` の `cp` 上書きを Puma が mmap している間に行うこと。cluster mode なら worker は master が再 fork するので数秒の 502 で済むが、single mode やコンテナ (LONG-OPS-02) では停止したままになる。
- **推奨対策**: `mmap_size` を 0 にする (64MB の `cache_size` があれば 45 万行の SQLite には十分) か、DB の差し替え・VACUUM は必ず「別ファイルに作って `mv` → 再起動」で行う運用にし、その旨をコメントとして `lib/db.rb` に書く。いずれにせよ LONG-OPS-02 の supervisor が前提。
- **確認状況**: `ローカルで再現` (1 回発生、再実行では再現せず。本番での発生条件は `推定`)

### <LONG-OPS-10> SQLite の PRAGMA が Puma worker に効いていない (fork 後の再接続で `cache_size` / `mmap_size` が既定値に戻る)
- **リスク度**: 低 (性能のみ、サイレント)
- **顕在化時期**: 初回デプロイ時から常に
- **場所**: `lib/db.rb:9-12`, `config/puma.rb:21,36-38` (`preload_app!` + `before_fork { DB.disconnect }`), gem: `sequel-5.103.0/lib/sequel/adapters/shared/sqlite.rb:337-345` (`connection_pragmas`), `adapters/sqlite.rb:150-156`
- **内容**: `journal_mode=WAL` は DB ファイルに永続化されるが、`synchronous` / `cache_size` / `mmap_size` は**接続ごと**の設定。`lib/db.rb` はプール内の最初の 1 接続にだけ `DB.run` している。`before_fork` で `DB.disconnect` した後、各 worker は要求時に新規接続を作る (Sequel の pool は `hold` 時に lazy 生成; `connection_pool/threaded.rb:60-61`) が、その接続には PRAGMA が流れない。ローカルで再現: `DB.disconnect` 直後の新接続は `cache_size=-2000` (2MB)、`mmap_size=0` (`synchronous` は 1 のまま)。Sequel の SQLite アダプタが接続時に自動で流す PRAGMA は `foreign_keys`, `case_sensitive_like`, `auto_vacuum`, `synchronous`, `temp_store` だけ (`shared/sqlite.rb:337-345`) で `cache_size`/`mmap_size` は含まれない。同じ理由で `max_connections` 既定 4 の 2〜4 本目の接続にも効かない。
  結果: 本番の全 worker は 2MB キャッシュで FTS/GROUP BY を回している。壊れはしないが、`docs/backend-review.md:46-47` の「64MB / 256MB」は事実ではない。
- **推奨対策**: `Sequel.connect(url, pool_timeout: 300, max_connections: 5, after_connect: proc { |c| c.execute_batch("PRAGMA synchronous=NORMAL; PRAGMA cache_size=-64000; PRAGMA mmap_size=0") })` のように `after_connect` で接続ごとに流す。
- **確認状況**: `ローカルで再現`

### <LONG-OPS-11> 外部サービス障害時に rescue されない例外があり、`/status` `/jobs/*` `/view` が 500 になる (NIG メンテナンスで定期的に起きる条件)
- **リスク度**: 中
- **顕在化時期**: 特定条件 (DDBJ/NIG スパコンの計画停止時、NCBI や chip-atlas.dbcls.jp が RST/経路不達を返す時。年に数回)
- **場所**: `lib/services/service_monitor.rb:82-83`, `lib/services/wabi_service.rb:116,147` および `:164-171` (`post` は rescue 無し), `lib/services/sapporo_service.rb:32,53,76`, `lib/services/sra_service.rb:46,57`, `lib/services/data_proxy.rb:67`, `lib/services/bed_extension_resolver.rb:105`。対照: `routes/api.rb:250-251` (`remote_url_status` は `ECONNRESET`, `EHOSTUNREACH` まで rescue)
- **内容**: 各サービスの rescue リストは `SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError` (+一部 `OpenSSL::SSL::SSLError`) で、**`Errno::ECONNRESET`, `Errno::EHOSTUNREACH`, `Errno::ENETUNREACH`, `EOFError`** (`BedExtensionResolver` だけ `IOError` 経由で `EOFError` を拾う) が漏れている。メンテナンス中のホストは接続拒否ではなく RST や無応答経路になることが多く、その場合:
  - `ServiceMonitor.check` が例外 → `/status` が 500 → フロントの機能無効化バナーが出ない (設計されたグレースフルデグレードが動かない)。`ComputeRouter.available_backend` も同じ経路なので `/jobs/available`, `/jobs/submit`, `/jobs/:id/status` が 503 ではなく 500。
  - `WabiService.post` (:169 `Net::HTTP.post_form`) は rescue が一切無く、タイムアウトすら `Timeout::Error` として上に抜ける → `/jobs/submit` 500。
  - `SraService` は `ECONNRESET`/`SSLError` を拾わないので `/view` ページ全体が 500 (NCBI の一時的な RST で実験ページが見えなくなる)。
  10 年運用ではこれらは「必ず何度も起きる」条件で、そのたびに `puma.stderr.log` にバックトレースが積まれる (LONG-OPS-06)。
- **推奨対策**: 共通のネットワーク例外リスト (`Net::HTTP` 系: `SocketError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EPIPE, Errno::ETIMEDOUT, Net::HTTPError`) を 1 箇所 (`lib/services/http_errors.rb`) に定義し全サービスで使う。`WabiService.post` に rescue を追加。加えて Sinatra の `error` ハンドラで `/api/*`, `/jobs/*`, `/status` は JSON 5xx を返す。
- **確認状況**: `ソース/設定で確認済み` (どの errno が出るかは `推定`)

### <LONG-OPS-12> Docker ビルドコンテキストに DB コピー (~2GB) と `metadata/` (1.5GB) が入り、イメージが数 GB になる
- **リスク度**: 低
- **顕在化時期**: `docker build` 実行時 (作業ディレクトリに DB コピーやメタデータが残っている場合)
- **場所**: `.dockerignore:4` (`database.sqlite` のみ。`database.sqlite.*` と `metadata/` は除外されない), `Dockerfile:3` (`COPY . /app`)
- **内容**: `.dockerignore` は `database.sqlite` を除外するが `database.sqlite.latest/.rebuild/.verify` (各 ~650MB) と `metadata/` (1.5GB) は除外していない。現状の作業ツリーで `docker build` すると 3.5GB 超のコンテキストが送られ、`COPY . /app` でイメージに焼き込まれる。`public/ExperimentList*.json` は :10-11 で除外済み。`Dockerfile:3-5` は `COPY .` の後に `bundle install` するので、コード 1 行の変更で gem レイヤも毎回やり直しになる (ビルド時間の問題のみ)。
- **推奨対策**: `.dockerignore` に `database.sqlite*`, `metadata/`, `*.sqlite*-wal`, `*.sqlite*-shm` を追加。`Dockerfile` は `COPY Gemfile Gemfile.lock ./` → `bundle install` → `COPY . .` の順にする。
- **確認状況**: `ソース/設定で確認済み`

### <LONG-OPS-13> コンパイル済み JS は git 管理外で、デプロイにも Docker イメージにも Node ビルド工程が無い (5 年後の再デプロイに未文書化の Node ツールチェーンが要る)
- **リスク度**: 中
- **顕在化時期**: 初回デプロイ時 (ビルド済み `public/js/*.js` が無い環境からデプロイした時) / 数年後の再デプロイ時
- **場所**: `.gitignore:24-48` (`public/js/*.js` を除外; `git ls-files public/js` は `bootstrap.bundle.min.js` のみ), `.dockerignore:14-18` (`frontend/` と `node_modules` を除外、「TypeScript is precompiled to public/js (no Node in the runtime image)」), `script/deploy/deploy.sh:229-265` (npm 無し), `.github/workflows/ci.yml:48-53` (CI だけが `npm ci && npm run build` する), `package.json:5-10` (`engines` 無し), `package-lock.json` (esbuild 0.21.5, typescript 5.9.3, @types/node 26.6.1 固定)
- **内容**: ページ JS (`views/layout.erb:20` の `/js/<page>.js`) はローカルで `npm run build` した成果物にのみ存在する。`deploy.sh` は git から取り出すだけなので**新インスタンスには JS が 1 つも無い** (`asset_path` は `File.exist?` が偽なら stamp 無しで返し、ブラウザは 404 → 各ページの動的部分が静かに動かない。エラーにはならない)。Docker イメージも `public/js` の事前ビルドに依存する。Node のバージョンは固定されておらず (`.nvmrc`/`engines` 無し)、README (`README.md`) と `docs/setup.md` にはビルド手順が一切無い。外部レジストリ不変の前提でも「どの Node で `npm ci && NODE_ENV=production npm run build` を叩くのか」は運用者の記憶頼み。
- **推奨対策**: CI (`ci.yml`) で作った `public/js` をリリース成果物として配布するか、`Dockerfile` を multi-stage (`node:22-slim` で build → `ruby:4.0.5-slim` にコピー) にしてビルドをイメージに閉じる。`package.json` に `"engines": {"node": ">=20 <27"}` と `.nvmrc` を置き、README に 5 行の手順を書く。
- **確認状況**: `ソース/設定で確認済み`

### <LONG-OPS-14> 監視・アラート・バックアップが無く、旧インスタンスも終了されない
- **リスク度**: 中
- **顕在化時期**: 常時 (障害に気付く手段が無い) / デプロイのたび (課金)
- **場所**: `script/deploy/deploy.sh:364-366, 393` (「Old instance is NOT terminated」), `script/maintenance/check_wabi.sh`, `script/maintenance/smoke_test.sh:98-114` (旧版の `/data/*`, `/browse`, `/download` を叩く), `routes/health.rb`
- **内容**:
  - repo に CloudWatch アラーム、外形監視、通知先の記述は無い。`/health` と `/status` はあるが誰も見ていない。`script/maintenance/smoke_test.sh` は旧版 API パス (`/data/experiment_types`, `/browse`, `/download`, `/wabi_chipatlas`) を叩くので新版では大半が FAIL し、監視に転用できない。
  - deploy のたびに旧インスタンスは ALB から外されるだけで**終了されない** (:364-366)。t3.medium は ap-northeast-1 で約 $40/月 (推定)。年 2 回のデプロイでも 10 年で 20 台 → 放置すれば月 $800 まで増える。ALB から外れたインスタンスは誰にも使われず、`apt-get upgrade` もされない。
  - インスタンス入れ替えで失われる状態: `sra_cache` (NCBI メタデータキャッシュ; 消えても再取得される。設計上許容)、`log/access_log*` (「クエリを記録している」と README:33 が利用者に約束している記録が消える)、`metadata/` (再ダウンロード可)、`database.sqlite` (再生成可)。いずれも許容範囲だが、どこにも「消えてよい」と書かれていない。
  - `database.sqlite` のバックアップは無い。メタデータ (chip-atlas.dbcls.jp) から `rake metadata:load` で再生成できるので不要 — ただしそれは LONG-OPS-08 の手順が生きている前提。
- **推奨対策**: (1) `deploy.sh` に `--terminate-old` (既定 ON、成功後 N 分待って terminate) を追加するか、少なくとも `aws ec2 create-tags --tags Key=ExpireAfter,Value=<date>` を付けて後で掃除できるようにする。(2) 外形監視 (`https://chip-atlas.org/health` を 5 分毎、JSON の `status=="ok"` を検査) と ALB `UnHealthyHostCount` の CloudWatch アラームをメール通知に繋ぐ。(3) `smoke_test.sh` を新版 API (`/api/*`, `/jobs/*`) に書き直す。(4) 「失って良い状態 / 再生成手順」を `docs/operations.md` に書く。
- **確認状況**: `ソース/設定で確認済み` (課金額は `推定`)

### <LONG-OPS-15> 運用文書が全て旧版のもの (Ruby 2.5.1 / unicorn / 旧 DB 配布 URL)
- **リスク度**: 中
- **顕在化時期**: 人が手を入れる必要が生じた最初の時点
- **場所**: `docs/setup.md:1-62` (Ubuntu 16.04 の kernel、`rbenv install 2.5.1`, `unicorn`, `wget http://data.dbcls.jp/~inutano/chip-atlas/sqlite/latest/database.sqlite`), `README.md` (旧版の説明のまま、ビルド・起動手順無し), `script/systemctl/README.md`, `script/launch-instance/README.md` (旧 AMI 前提), `SHIKINEN-SENGU.md:851` ("Docker + Unicorn + NGINX")
- **内容**: 新版を起動する正しい手順 (`bundle install` → `rake db:migrate` → `rake metadata:load` → `npm ci && npm run build` → `bundle exec puma -C config/puma.rb`) はどのファイルにも書かれていない。10 年後に障害対応する人は、`docs/setup.md` に従って Ruby 2.5.1 と unicorn を入れようとする。`Rakefile` の `metadata:*` タスクには `desc` が無いので `rake -T` にも出ない。
- **推奨対策**: `docs/setup.md` を新版手順に書き換え (旧内容は削除)、`README.md` に「Running」節を 10 行で追加、`script/systemctl/` と `script/launch-instance/*_info.json` (実インスタンス ID・アカウント ID・セキュリティグループ ID を含む) を削除する。
- **確認状況**: `ソース/設定で確認済み`

### <LONG-OPS-16> `ExperimentSearch.total_count_cache` はユーザ入力 (`genome` パラメータ) をキーにした無期限・無制限キャッシュ
- **リスク度**: 低
- **顕在化時期**: 数年 (スキャナが `/api/search?genome=<乱数>` を大量に送った場合は数日)
- **場所**: `lib/models/experiment_search.rb:72-87` (`total_count_cache[key] ||= ...`), `:126-127` (`list_all` から呼ばれる), `routes/api.rb:94-101` (`genome` は検証されない)
- **内容**: `q` 無しの `/api/search?genome=X` は任意の文字列 X をキーに `{X => 0}` をメモ化する。有効期限も上限も無く、Puma worker が生きている限り増える (1 エントリ数十〜数百 B なので、100 万通り叩かれて数百 MB)。同時に、メタデータ再ロード後も再起動まで値が古い (LONG-OPS-08)。他のキャッシュは有界: `BedExtensionResolver` 2000 件 FIFO (bed_extension_resolver.rb:30,119-126)、`TargetGenesTsv` 150MB 予算 (target_genes_tsv.rb:62,268-286)、`ServiceMonitor` 3 キー、`Experiment.@index_cache` 1 件 1h。
- **推奨対策**: `genome` を `ChipAtlas::Experiment.genomes.key?(genome)` で検証し、未知なら空結果を返してキャッシュしない。または `total_count_cache` に TTL (1h) を付ける。
- **確認状況**: `ソース/設定で確認済み` (ローカルでの確認は、確認しようとした時点でサーバが LONG-OPS-09 で落ちていたため未実施)

### <LONG-OPS-17> Sequel の接続プール (既定 4) が Puma のスレッド数 (5) より少なく、`pool_timeout: 300` は nginx の `proxy_read_timeout 120s` より長い
- **リスク度**: 低
- **顕在化時期**: 特定条件 (5 スレッド同時に DB を触る高負荷時)
- **場所**: `lib/db.rb:7` (`pool_timeout: 300`、`max_connections` 未指定), `config/puma.rb:17-18` (`threads 5, 5`), `config/nginx/chip-atlas.conf:75` (`proxy_read_timeout 120s`), gem: `sequel-5.103.0/lib/sequel/connection_pool/threaded.rb:28` (既定 4)
- **内容**: ローカルで `DB.pool.max_size` は 4 (`Sequel::TimedQueueConnectionPool`)。worker あたり 5 スレッドのうち 5 本目は接続待ちになり、最長 300 秒待つ。nginx は 120 秒で 504 を返すので、クライアントには 504、Puma スレッドはさらに 180 秒占有されたまま。SQLite の読みは ms 単位なので通常は起きないが、FTS の重い検索や TargetGenes の 4MB TSV 解析が重なると顕在化する。
- **推奨対策**: `max_connections: ENV.fetch('MAX_THREADS', 5).to_i` を `Sequel.connect` に渡し、`pool_timeout` は 10〜30 秒に下げて早く失敗させる。
- **確認状況**: `ローカルで再現` (max_size=4 を確認)

### <LONG-OPS-18> Puma にメモリ上限・定期再起動が無く、RSS は高水位に張り付く
- **リスク度**: 低
- **顕在化時期**: 数ヶ月〜数年 (t3.medium 4GB なら余裕はある)
- **場所**: `config/puma.rb` (`worker_timeout 60` のみ。`fork_worker`, メモリ監視無し), `lib/services/target_genes_tsv.rb:36-51,62`
- **内容**: `TargetGenesTsv` のキャッシュ上限 150MB は「推定バイト数」(行数 × (40 + 8 × 列数)) で、文字列列やハッシュのオーバーヘッドを含まないので実 RSS は 2 倍程度になり得る (コメント :36-51 も自認)。Ruby のヒープは解放してもプロセスに戻りにくく、2 worker × (baseline ~120MB + キャッシュ実測 ~300MB) ≈ 1GB 弱で高止まりする。t3.medium (4GB、`InstanceType` は `script/launch-instance/app-20260319-121052_info.json:127`) では OOM にはならない見込みだが、上限や再起動が無いので、より小さいインスタンスに変えた瞬間に OOM killer 案件になる。`worker_timeout 60` (:24) は master への check-in 監視であり、メモリや長時間リクエストの制御ではない。
- **推奨対策**: systemd unit に `MemoryMax=2G` + `Restart=always` (LONG-OPS-02 と同じ unit)、または `puma_worker_killer` 相当で worker あたり 700MB を超えたら再起動。
- **確認状況**: `ソース/設定で確認済み` (RSS の数字は `推定`)

### <LONG-OPS-19> `sra_cache` は増える一方 (`clear_expired` はどこからも呼ばれない)
- **リスク度**: 低
- **顕在化時期**: 数年 (上限は実験数 ~45 万件 × ~0.5KB ≈ 数百 MB)
- **場所**: `lib/models/sra_cache.rb:37-40` (`clear_expired`)、呼び出し元は `test/models/sra_cache_test.rb:40` のみ。`lib/services/sra_service.rb:16-23`
- **内容**: `/view` されるたびに 1 行 upsert (`experiment_id` unique なので同じ実験は増えない)。30 日 TTL を過ぎた行は `get` で無視され再取得で上書きされるだけで削除はされない。ローカル `database.sqlite.verify` では 2 行 / 平均 504 バイト。全実験が閲覧されても数百 MB。これが唯一の稼働中書き込みなので WAL のチェックポイント (`wal_autocheckpoint=1000`) も問題無く回る。
- **推奨対策**: `metadata:load` の末尾か、月次の `rake sra_cache:clear_expired` タスクで `SraCache.clear_expired` を呼ぶ。急ぎではない。
- **確認状況**: `ソース/設定で確認済み` (行数・サイズはローカルで確認)

### <LONG-OPS-20> CI は master のみ、docker-compose.dev.yml は Ruby 3.3、GitHub Actions のピン留めは数年で陳腐化
- **リスク度**: 低
- **顕在化時期**: 数年
- **場所**: `.github/workflows/ci.yml:3-7` (`branches: [master]`), `docker-compose.dev.yml:4` (`ruby:3.3-slim`) vs `Dockerfile:1` (`ruby:4.0.5-slim`), `Gemfile.lock` (`BUNDLED WITH 2.5.3`; ロックは Ruby 4.0 で解決: `minitest 6.0.2`, `prism 1.9.0`, `bigdecimal 4.1.0`)
- **内容**: sengu ブランチは CI で一度も検証されずにデプロイ対象になる。`docker-compose.dev.yml` は Ruby 3.3 で `bundle install` するので、Ruby 4.0 前提のロックと合わず失敗し得る。`ubuntu-latest` の中身と `actions/*@v4`, `ruby/setup-ruby@v1`, `aws-actions/configure-aws-credentials@v4` は GitHub 側の都合で数年ごとに更新を強いられる (GitHub 不変の前提から外れるが記録)。
- **推奨対策**: `ci.yml` の `branches` に `sengu` を足す (マージ後は不要)。`docker-compose.dev.yml` を `ruby:4.0.5-slim` に揃えるか削除。
- **確認状況**: `ソース/設定で確認済み`

### <LONG-OPS-21> `/health` は `experiments` テーブルが無い DB では 503 ではなく 500 になる
- **リスク度**: 低
- **顕在化時期**: 特定条件 (空 DB でコンテナ起動、`db:migrate` 前、`db:reset` 中)
- **場所**: `routes/health.rb:11-19` (`:19` の `DB[:experiments].count` は `begin/rescue` の外)
- **内容**: `DB.test_connection` は成功するが `DB[:experiments].count` が `Sequel::DatabaseError` を投げ、ハンドラ外なので Sinatra の 500 HTML になる。ヘルスチェック側から見れば unhealthy には違いないが、JSON で原因を返す設計意図 (`checks[:database_error]`) が空 DB では働かない。`docker-compose.yml` にボリュームが無い (LONG-OPS-02) ので、Docker 経路ではこれが初回の応答になる。
- **推奨対策**: `:19` を `begin/rescue` 内に移し、失敗時は `checks[:experiments] = 'error'` として 503 JSON を返す。
- **確認状況**: `ソース/設定で確認済み`

---

## 問題なしと確認した項目

- **2038 年問題 / タイムスタンプ**: Sequel の SQLite アダプタは `DateTime` 列を `'%Y-%m-%d %H:%M:%S.%6N%z'` の TEXT で書く (`sequel-5.103.0/lib/sequel/adapters/shared/sqlite.rb:936-938`; ローカルで `typeof(fetched_at) = "text"`, 値 `2026-09-21 17:17:48.761132 +0000` を確認)。`Time.now - row[:fetched_at]` (sra_cache.rb:18) も Ruby の Time なので 2038 年を越えても問題無い。
- **日付・年のハードコード**: アプリコード (`app.rb`, `routes/`, `lib/`, `views/*.erb`, `config/`) に年のリテラルは無い。`views/updates.markdown` / `views/publications.markdown` の年は履歴表示のみ。`frontend/components/job-tracker.ts:84` の `+09:00` は WABI の request-ID (JST) の解釈で、外部仕様に従う値。
- **`Time#iso8601`** (app.rb:57): Ruby 3.4 以降コアに入っているので `require 'time'` 無しでも動く (Ruby 4.0.5)。ログの時刻はプロセスの TZ (コンテナは UTC、`docs/setup.md:19` のインスタンスは Asia/Tokyo) で `+00:00`/`+09:00` が付くので曖昧さは無い。
- **Logger のマルチプロセスローテーション**: `logger-1.7.0` の `lock_shift_log` (log_device.rb:177-206) は `flock` + inode 比較で、`preload_app!` により 2 worker が同じ fd を継承していても二重ローテーションや書き込み欠落は起きない (削除しないことは LONG-OPS-06)。
- **fork 後の DB 再接続**: `before_fork { DB.disconnect }` (puma.rb:36-38) の後、Sequel のプールは `hold` 時に新規接続を lazy に作る (`connection_pool/threaded.rb:60-61, 74-80`) ので `on_worker_boot` での明示的再接続は不要 (PRAGMA が流れない件のみ LONG-OPS-10)。
- **WAL の肥大**: 稼働中の書き込みは `sra_cache` の upsert だけ。`wal_autocheckpoint=1000` (既定、ローカルで確認) で都度チェックポイントされ、`database.sqlite.verify-wal` は 0 バイト。読み取り専用トラフィックでは WAL は増えない。
- **Puma の stale pidfile**: `puma-7.2.0/lib/puma/launcher.rb:324-332` の `write_pid` は既存ファイルを検査せず上書きするので、クラッシュ後に `tmp/pids/puma.pid` が残っていても再起動は阻害されない。
- **Puma `worker_timeout 60`** (puma.rb:24): master への check-in 監視。DSL (`puma/dsl.rb:1135-1143`) は `worker_check_interval` (既定 5) より大きければよく、設定値は妥当。
- **本番の TLS 証明書**: issuer `Amazon RSA 2048 M01`、期限 2027-01-02。ACM 管理なので人手の更新は不要 (検証用 DNS レコードが残っている前提: 未確認)。
- **nginx のアクセスログ**: Ubuntu の nginx パッケージは `/etc/logrotate.d/nginx` を同梱する (daily / 14 世代 / compress) ので、アプリ側ログと違い肥大しない (推定)。
- **`BedExtensionResolver` / `TargetGenesTsv` / `ColoTsv` / `ServiceMonitor`**: それぞれ 2000 件 FIFO (bed_extension_resolver.rb:30,126)、150MB 予算 FIFO (target_genes_tsv.rb:62,281-286)、キャッシュ無し (colo_tsv.rb:47-56)、3 キー固定 (service_monitor.rb:14-18)。長期稼働で無限に増える構造ではない。スレッド非安全 (両者のコメント :22-24 / :58-59) は GVL 下では二重プローブ程度で、破綻はしない。
- **ホスト認可の許可範囲**: `'.chip-atlas.org'` は `chip-atlas.org` 自身とサブドメインの両方を許可する (host_authorization.rb:43-46; MockRequest で確認)。ドメインが変わらない限り 10 年動く。
- **Sinatra の環境判定**: Puma は `environment` 設定を `ENV['RACK_ENV']` に書く (`puma/launcher.rb:362-364`)、Sinatra は `APP_ENV || RACK_ENV` を見る (`sinatra/base.rb:1940`) ので、`Dockerfile:7` や systemd から `RACK_ENV` 無しで起動しても production 設定 (ホスト認可、ログのファイル出力) になる。

## 未確認・不確実事項

- **ALB の設定** (target group の health check path / port / matcher、リスナが 80→443 リダイレクトするか、ターゲットへ HTTP か HTTPS か) は AWS コンソールが無いと分からない。本番の応答 (80 番が 200、IP Host で 403) から「ALB → インスタンス 80 番 HTTP、matcher は 403 を許容しているか `/health` 以外を見ている」と推定した。
- **AMI の OS バージョン**: nginx 1.18.0 から Ubuntu 20.04 または 22.04 と推定。どちらかで LONG-OPS-05 の顕在化日が 2 年変わる。`ami-047c61fea594d4c5f` の中身 (rbenv の Ruby、`/etc/init.d/chip-atlas` の有無、certbot の有無、unattended-upgrades の設定、ルート EBS サイズ) も未確認。
- **`deploy.sh` が過去に成功したことがあるか**: `deploy-*.log` は `.gitignore:16-17` で除外されており不明。内容からは新版に対して成功したことは無いと判断できる。
- **LONG-OPS-09 (SIGBUS) の本番での再現性**: ローカル 1 回のみ、Docker Desktop の bind mount 固有の可能性が高い。本番 EBS では「稼働中の truncate/VACUUM」が無ければ起きない見込みだが、実機で試していない。なお、この事故で停止していたローカルコンテナは私が 14:21Z 頃 `docker start chip-atlas-local` で復旧させた (同じ CMD で再起動、`/health` 200 を確認)。以降の他エージェントの計測はこの再起動後の状態。
- **sra_cache と access_log の実際の成長率**: 本番のアクセス量が分からないため、LONG-OPS-06/19 の時期は桁の見積もり。
- **旧インスタンス放置の実態** (現在 AWS アカウントに何台残っているか) と月額は推定。
- **Ruby 4.0 / Debian 13 / Ubuntu の EOL 日付**: 各プロジェクトの慣例からの推定で、公式アナウンスは未確認。
- **ブラウザでしか確認できない事項**: 本件の範囲では無し。
