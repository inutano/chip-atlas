# SEC-INF: インフラ・デプロイ・リポジトリ衛生 セキュリティ監査

対象: `/Users/inutano/repos/chip-atlas` (sengu ブランチ)。本番 = AWS EC2 + nginx + Puma + ALB。リポジトリは public (`inutano/chip-atlas`, `visibility: public` を API で確認)。

## 担当範囲の要約と総評

- **最重要の構図**: デプロイ自動化一式 (`script/deploy/deploy.sh`, `.github/workflows/deploy.yml`, `script/systemctl/chip-atlas`, `docs/setup.md`) は**旧 Unicorn 版のまま更新されておらず** (old-app の deploy.sh / deploy.yml と `diff` で **完全一致**)、Puma 化した新版に対して動かない。`git reset --hard origin/master` → 存在しない `rake pj:load_metadata` → 存在しない `unicorn` 起動、と 3 段で失敗する。加えて新 nginx 設定が `:80` を全て 301 に飛ばすため、deploy.sh 自身のヘルスチェック (`http://IP/health`) も ALB ヘルスチェックも 200 を得られない。これは**セキュリティというより可用性・供給網の問題**だが、監査範囲の芯なので High として複数計上する。
- **情報漏洩**: public リポジトリに `script/launch-instance/app-20260319-121052_info.json` が commit されており、AWS アカウント ID・SG/Subnet/VPC ID・プライベート IP・MAC・ENI ID・KeyName・AMI ID・Launch Template ID が露出 (High)。原因は `.gitignore` のプレフィックス変更漏れ。
- **ハードコードされた鍵・パスワードは作業ツリー・git 全履歴ともに検出されず** (`AKIA...`, 秘密鍵ブロック, `aws_secret` 等の強パターン 0 件; ヒット 2 件はいずれも `${{ secrets.* }}` / `${MINIO_*}` の**参照**でリテラルではない)。`deploy.conf` / `launch-chip-atlas.conf` / `.env` は履歴に一度も入っていない。ここは良好。
- **プライバシー**: `app.rb#log_activity` が全 POST の JSON ボディ (ジョブ投入の遺伝子リスト・BED 内容) と `request.ip` を平文で記録 (実ログに 27KB 行を確認)。保持期間の上限なし、Puma ログはローテーションなし (Medium)。
- **供給網/権限**: master にブランチ保護なし、`environment: production` は実体が存在せず保護規則ゼロ、workflow の `permissions:` 未宣言でトークンが write、第三者 Action は tag 固定 (SHA 未固定)、secret scanning 無効。SSH は `StrictHostKeyChecking=no`。
- 依存関係は sengu で大幅に削減 (nokogiri/activerecord/redcarpet/unicorn は Gemfile.lock から消滅、master には 21 箇所残存)。残る rack 3.2.5 等に既知 advisory はあるが到達性は限定的。
- 深刻度内訳: **Critical 0 / High 6 / Medium 5 / Low 4 / Info 複数**。

---

## High

### SEC-INF-01 デプロイ provisioning が Unicorn 前提のまま (Puma 化に非追従)
- **深刻度**: High
- **種別**: 設定不備 / 可用性 / 供給網 (correctness)
- **場所**: `script/deploy/deploy.sh:255-261`, `script/systemctl/chip-atlas:18,22`, `script/systemctl/README.md:37,41`, `docs/setup.md:47,57,61`
- **内容**: provisioning heredoc はアプリ再起動を Unicorn で行う:
  ```
  if [ -f tmp/pids/unicorn.pid ] && kill -0 $(cat tmp/pids/unicorn.pid) ...; then
      kill -USR2 $(cat tmp/pids/unicorn.pid); ...
  else
      bundle exec unicorn -c unicorn.rb -D
  fi
  ```
  しかし新版は Puma (`config/puma.rb`, `Gemfile` に `gem 'puma'`, `Dockerfile` CMD が `puma`)。作業ツリーに `unicorn.rb` は**存在せず** (`git ls-files | grep -c unicorn` = 0)、Gemfile に unicorn gem もない。`systemctl/chip-atlas` も `bundle exe unicorn -c unicorn.rb -E production -D` のまま。よって「Puma を止めずに Unicorn を起動しようとして失敗、または何も起動しない」。
- **攻撃シナリオ**: 攻撃ではなく自爆。sengu を master にマージ後この経路でデプロイすると、アプリが起動せず全断。
- **本番影響**: deploy.sh は old-app のものと**バイト単位で一致** (diff 済) = 旧 Unicorn 時代の遺物。Puma 用に `config/puma.rb` を使う起動/再起動 (例 `systemctl restart chip-atlas` を Puma unit 化 or `pumactl phased-restart`) に総入れ替えが必要。
- **推奨対策**: provisioning を `bundle exec puma -C config/puma.rb` ベースへ書き換え、`script/systemctl/chip-atlas` を Puma 用 systemd unit に置換、`docs/setup.md` を Ruby 4.0.5 / Puma / 現行データ URL に更新。
- **確認状況**: `ローカルで実証済み` (ファイル内容・`git ls-files`・old-app との diff)。

### SEC-INF-02 provisioning が存在しない Rake タスク `pj:load_metadata` を呼ぶ
- **深刻度**: High
- **種別**: 設定不備 / 可用性
- **場所**: `script/deploy/deploy.sh:252-253`
- **内容**: `bundle exec rake pj:load_metadata` を実行するが、`Rakefile` + `lib/tasks/*.rake` に `pj` 名前空間は**存在しない**。実在するのは `db:migrate` / `db:reset` (`Rakefile:10-24`)、`db:clean_old_genomes` (`lib/tasks/clean_old_genomes.rake:3-5`)、`metadata:load` 系 (`lib/tasks/metadata.rake:18,70,86,101,109,128`) のみ。`grep -rn "namespace\|task :" Rakefile lib/tasks` で確認。
- **攻撃シナリオ**: 自爆。heredoc は `set -euo pipefail` なので `rake` の未知タスク非ゼロ終了で provisioning が中断する (SEC-INF-01 の unicorn 起動行に到達すらしない)。
- **本番影響**: デプロイが確実に途中失敗。正しくは `rake metadata:load` (ただしこれは毎回上流から数百 MB を再取得し全テーブルを delete→再ロードする破壊的タスク。デプロイ時に走らせる設計自体を再検討すべき)。
- **推奨対策**: `pj:load_metadata` を実在タスクに修正するか、メタデータ再ロードをデプロイから分離。
- **確認状況**: `ローカルで実証済み`。

### SEC-INF-03 新 nginx 設定 + host_authorization が ALB / デプロイのヘルスチェックを破壊
- **深刻度**: High
- **種別**: 設定不備 / 可用性
- **場所**: `config/nginx/chip-atlas.conf:5-9,11-13,56-65,79-81`, `app.rb:70-72`, `script/deploy/deploy.sh:283-284`
- **内容**: 新設定は `:80` を `server_name chip-atlas.org` の単一 server で受け**全リクエストを `return 301 https://...`** する。これに対し:
  1. deploy.sh のヘルスゲートは `curl http://$NEW_INSTANCE_IP/health` = **HTTP:80** を叩き `[[ "$status_code" == "200" ]]` を待つ。ローカルで verbatim 設定を nginx1.18 に載せて実証 → `Host: <IP>` でも `Host: chip-atlas.org` でも **301** が返り、200 は永久に来ない (`deploy.sh:298` の die に到達)。
  2. ALB ヘルスチェックの Host ヘッダは AWS 仕様上**ターゲットのプライベート IP 固定** (AWS 公式: "The host header value contains the private IP address of the target"、変更不可)。`:443` に来た場合 nginx→`location / try_files @app`→Puma へ `proxy_set_header Host $host` で IP がそのまま渡り、`configure :production` の `host_authorization {permitted_hosts:['.chip-atlas.org']}` が IP を**非許可 → 403 "Host not permitted"**。`:80` に来た場合は上記 301。いずれも既定 matcher (200) と不一致。
- **攻撃シナリオ**: 攻撃ではなく可用性。ALB が全ターゲットを unhealthy と判定 → fail-open で無理やり流すか、デプロイの ALB 登録 (`deploy.sh:315-337`) が `die "did not become healthy"` で失敗。
- **本番影響**: 旧 nginx (`old-app/config/nginx/chip-atlas.conf`) は `server_name _;` の catch-all・平文・リダイレクト無しで、IP Host の `/health` にも 200 を返せた。新設定はこの前提を崩す**リグレッション**。実際の ALB リスナ (HTTP:80 か HTTPS:443 か) と matcher 設定は AWS コンソールでしか確認できず要検証だが、既定値なら確実に破綻する。
- **推奨対策**: (a) ALB のヘルスチェック用に `server { listen 80 default_server; location = /health { proxy_pass ...; } }` を分離し 301 対象から外す、または (b) `app.rb` の permitted_hosts に ALB がヘルスチェックに使う Host (IP/内部名) を許可、もしくは `allow_if` で `/health` を素通し。deploy.sh のゲートも実際のリスナに合わせる。
- **確認状況**: `ローカルで実証済み` (nginx verbatim 挙動) + `要追加検証` (ALB リスナ/matcher の実設定)。

### SEC-INF-04 デプロイ時にフロントエンドをビルドしない + `public/js/*.js` は gitignore → JS が消える
- **深刻度**: High
- **種別**: 設定不備 / 可用性
- **場所**: `script/deploy/deploy.sh:228-264` (heredoc に npm/esbuild 手順なし), `.gitignore:24-48`, `esbuild.config.mjs`
- **内容**: ページ JS (`public/js/homepage.js`, `search.js`, `peak-browser.js` … 全 14 本 + `.map`) は `.gitignore:26-48` で除外され、tracked なのは `public/js/bootstrap.bundle.min.js` のみ (`git ls-files public/js` で確認)。provisioning は `git fetch` + `git reset --hard origin/master` の後 `bundle install` しかせず、`npm ci && npm run build` を**実行しない**。`views/layout.erb:20` は各ページで `<script type="module" src="/js/#{@page_js}.js">` を読む。
- **攻撃シナリオ**: 自爆。`git reset --hard` で作業ツリーがクリーンになると未 commit のビルド生成物は消え、新インスタンスには最初から存在しない → 全インタラクティブページの JS が 404 → サイト機能停止。
- **本番影響**: Peak Browser / Enrichment / Diff / Target Genes / Colo / Search / Experiment すべてが素の HTML だけになる。
- **推奨対策**: provisioning に `npm ci && NODE_ENV=production npm run build` を追加 (Node ランタイムが必要)、あるいはビルド済み `public/js/*.js` を成果物として配布 (AMI 焼き込み or artifact)。CI (`ci.yml:48-53`) はビルドするがデプロイ経路に繋がっていない。
- **確認状況**: `ローカルで実証済み` (`.gitignore` + `git ls-files` + heredoc 内容)。

### SEC-INF-05 public リポジトリに AWS インスタンス情報 JSON を commit (情報漏洩)
- **深刻度**: High
- **種別**: 情報漏洩
- **場所**: `script/launch-instance/app-20260319-121052_info.json` (5232 bytes, tracked)。同 `app-20260319-120517_info.json` は 0 byte。
- **内容**: `aws ec2 run-instances` の生出力がそのまま commit され、以下が public に露出:
  - AWS アカウント ID / OwnerId (`9059...`、12 桁)
  - Security Group `sg-0...` (`ChIP-Atlsa-Default-SG`)、Subnet `subnet-...`、VPC `vpc-...`
  - プライベート IP `10.1.1.252` / PrivateDnsName `ip-10-1-1-252`、MAC `06:a3:54:db:3a:7b`、ENI ID `eni-0d73a4bcad3ba7c20` / AttachmentId
  - **KeyName** (`chip...` = SSH キーペア名)、ImageId `ami-...`、Launch Template ID `lt-0dceffe78954c3e10`、InstanceType `t3.medium`、AZ `ap-northeast-1`
  (値はマスクして報告。フルは当該ファイル参照。)
- **攻撃シナリオ**: 攻撃者がリポジトリを閲覧 → アカウント ID とネットワーク構成 (VPC/Subnet/SG/プライベート CIDR `10.1.x`) を把握。単体では侵入不可だが、別途 IAM 資格情報や SSH 鍵が漏れた際の**標的特定を容易化**し、ソーシャルエンジニアリング/リソース列挙の足がかりになる。KeyName・SG 名の露出は特に不要な手がかり。
- **本番影響**: 現行 3.19 の一時インスタンス情報。account_id は `deploy.conf` で照合に使う値でもあり、露出は資格情報照合の秘匿性を下げる。
- **推奨対策**: 2 ファイルを `git rm` し、`.gitignore` に `script/launch-instance/*_info.json` を追加 (現状 `temporalInstance*` しかカバーせず、リネーム後の `app-*_info.json` に**マッチしない** — `git check-ignore` で NOT IGNORED 確認済)。既に公開済みのため account/SG 露出は許容するか、必要なら履歴の除去 (filter-repo) と KeyName ローテーションを検討。
- **確認状況**: `ローカルで実証済み`。原因コミット: `a1821ea` (2026-04-04, sengu)。プレフィックスを `temporalInstance-` → `app-` に変えた `cfc6f08` が gitignore 更新を伴わなかったのが根本。

### SEC-INF-06 デプロイの信頼境界が緩い (master 無保護 / 環境保護なし / トークン write / 無署名 pull)
- **深刻度**: High
- **種別**: 供給網 / 認可
- **場所**: `.github/workflows/deploy.yml:4-24,36-49`, `script/deploy/deploy.sh:234,240-241`
- **内容**: 複合的な信頼の緩さ:
  - `deploy.yml` は `workflow_dispatch` で `environment: production` を宣言するが、`gh api .../environments` は `total_count: 0` = **production 環境は実在せず**、必須レビュー・ブランチ制限などの保護規則はゼロ。
  - master に**ブランチ保護なし** (`branches/master/protection` → 404 "Branch not protected")、rulesets も空。
  - 両 workflow に `permissions:` 宣言がなく、リポジトリ既定が `default_workflow_permissions: write` + `can_approve_pull_request_reviews: true` (API で確認) → `GITHUB_TOKEN` が read/write。デプロイにも CI にもトークン権限は不要。
  - provisioning は `git reset --hard origin/master` を ubuntu ユーザで実行し、**コミット署名検証なし**。EC2 上は sudo パスワードレス前提 (`sudo apt-get`, `sudo cp/ln/nginx/systemctl` を無認証で実行)。
- **攻撃シナリオ**: master に push できる者 (collaborator 3 名、保護なし) が任意コードを push → 次回デプロイで prod が `git reset --hard` してそのまま実行。write 権限を持つ誰でも `workflow_dispatch` で本番デプロイを起動可能 (承認ゲートなし)。トークンが write のため、workflow 内で悪意ある step が混入すればリポジトリ改変も可能。
- **本番影響**: 単一の push 権限 = 本番コード実行権限。ブラスト半径が大きい。
- **推奨対策**: master にブランチ保護 (必須レビュー + 必須 CI + 直 push 禁止 + force-push 禁止)、production Environment を実際に作成し required reviewers を設定、各 workflow に `permissions: contents: read` (deploy は必要最小限のみ)、`can_approve_pull_request_reviews` を無効化、可能なら署名コミット検証。
- **確認状況**: `ローカルで実証済み` (GitHub API 応答 + スクリプト内容)。

---

## Medium

### SEC-INF-07 アクセスログに client IP + ジョブ投入の全 JSON ボディ (遺伝子/BED) を平文記録・保持無制限
- **深刻度**: Medium
- **種別**: ログ / 情報漏洩 (プライバシー) / DoS(ディスク)
- **場所**: `app.rb:49-60,63-68`, `routes/api.rb:99,169,210`, `routes/jobs.rb:52-58,127`, `config/puma.rb:31-33`
- **内容**: `parsed_json` (app.rb:49-54) が**全 POST の解析済みボディを** `log_activity(request.path_info, data)` で記録。`log_activity` は `Time.now.iso8601 \t request.ip \t action \t JSON.generate(data)` を `log/access_log` に書く。`/jobs/submit` はこの経路で**ユーザの遺伝子リスト・BED 座標・タイトル等を丸ごと**記録する (ローカル実ログ `log/access_log.20260921` に 1 行 27,320 文字の `/jobs/submit {"type":"enrichment_analysis","params":{...bedAFile...}}` を確認)。`search` / `target_genes` / `colo` はクエリ文字列も記録。`Logger.new('log/access_log', 'daily')` は日次ローテーションのみで**保持上限 (件数/日数) なし**、`log/` に 2026-04 以降のファイルが累積。Puma の `stdout_redirect ... true` は追記のみでローテーションなし (`log/puma.stderr.log` に既にスタックトレース 44KB)。
- **攻撃シナリオ**: 攻撃というより GDPR 的リスク。IP + 検索語 + 投入 BED/遺伝子は個人特定可能性のあるデータ。サーバ侵害・バックアップ流出時に研究上の未公開クエリと IP が漏れる。長期的にはディスク枯渇。
- **本番影響**: README「Disclaimer」でクエリ記録は告知済み (緩和)。ただしフル JSON ボディ・IP の平文・無期限保持は告知範囲を超えうる。
- **推奨対策**: ジョブ投入は識別子/サイズのみ記録し BED/遺伝子本文は記録しない (もしくはハッシュ/切り詰め)、IP は匿名化/短期保持、logrotate + 保持期間ポリシー、Puma ログもローテーション対象に。
- **確認状況**: `ローカルで実証済み`。

### SEC-INF-08 SSH が `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` (初回 MITM)
- **深刻度**: Medium
- **種別**: 設定不備 / 供給網
- **場所**: `script/deploy/deploy.sh:25,205,228`
- **内容**: `SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ..."`。ホスト鍵検証を完全に無効化し、既知ホストも保存しない。provisioning heredoc (`ssh ... bash -s`) をこの設定で流す。
- **攻撃シナリオ**: 新インスタンスへの初回 SSH で経路上の中間者が偽ホスト鍵を提示すると、警告なく接続が成立し、provisioning で送る内容 (デプロイコマンド) が攻撃者に渡り、応答も偽装可能。パブリック IP への SSH のため経路は完全には信頼できない。
- **本番影響**: 実際には同一 AWS リージョン内で短時間の接続であり悪用難度は中。ただし検証を切る必然性はない。
- **推奨対策**: launch 時に EC2 インスタンスのホスト鍵を API/コンソール出力から取得して `known_hosts` に投入、`StrictHostKeyChecking=accept-new` 以上に。少なくとも `/dev/null` は避けて一時 known_hosts を使う。
- **確認状況**: `コード上の推定` (経路 MITM は環境依存)。

### SEC-INF-09 nginx が public/ 全体を配信・レート制限/HSTS/CSP/server_tokens 未設定
- **深刻度**: Medium
- **種別**: 情報漏洩 / DoS / 設定不備
- **場所**: `config/nginx/chip-atlas.conf:18-19,23,26-42,79-81` (+ 未設定項目)
- **内容**: verbatim 設定をローカル nginx1.18 に載せて実測 (`Host: chip-atlas.org`, TLS):
  - `location / { try_files $uri @app; }` により `public/` 配下が**全て直配信**: `/ExperimentList_adv.json` 200 (170,745,570 byte)、`/ExperimentList.json` 200 (44,110,965 byte)、`/analysisList.tab` 200、`/tables/lineNum.tsv` 200、`/openapi.yaml` 200、`/llms.txt` 200、`/examples/hg38/geneA.txt` 200。
  - **ソースマップ露出**: `/js/homepage.js.map` 200、`/js/peak-browser.js` 200。`.map` は TypeScript 原本を復元でき、内部実装が読める。
  - `client_max_body_size 16m` は機能 (17MB POST → nginx が **413** を返すことを実証)。
  - **HSTS / CSP / Referrer-Policy なし** (静的ヒットのレスポンスヘッダに `Strict-Transport-Security` 等が出ないことを実証。本番 `curl -I` でも HSTS 無し)。アプリ側は rack-protection 由来の `X-Frame-Options: SAMEORIGIN` / `X-Content-Type-Options: nosniff` / `X-XSS-Protection` は付与 (確認済) だが nginx 直配信の静的ファイルには付かない。
  - `server_tokens` 未設定 → `Server: nginx/1.18.0 (Ubuntu)` を露出 (ローカル・本番とも)。nginx 1.18.0 は EOL 系で既知 CVE あり。
  - `limit_req` 等のレート制限**なし**。`/jobs/submit`・`/api/search`・`/api/colo` (TSV を上流から取得) 等の重い/外部投入エンドポイントが無制限。
- **攻撃シナリオ**: 163MB + 44MB の JSON を並列 GET するだけで帯域/メモリを圧迫 (増幅 DoS)。`.map` から実装詳細を取得。`/jobs/submit` を連打して DDBJ WABI へ大量ジョブを中継させる (下流の共有計算資源への DoS 踏み台)。
- **本番影響**: `robots.txt` は `/api` `/data` 等を Disallow するが強制力なし。大容量 JSON は新版フロントでは未使用 (`grep` で参照なし、旧 /search 専用) なので**そもそも public から消してよい**。
- **推奨対策**: 未使用の `ExperimentList*.json` を public から除去、`.map` は本番非配信 (別 location で 404 or 認証)、`server_tokens off;`、`add_header Strict-Transport-Security`/`Referrer-Policy`/最小 CSP、`limit_req_zone` + ジョブ/検索エンドポイントに `limit_req`。
- **確認状況**: `ローカルで実証済み` (nginx verbatim 挙動) + 本番ヘッダ確認。

### SEC-INF-10 GitHub Actions の第三者 Action が tag 固定 (SHA 未固定)
- **深刻度**: Medium
- **種別**: 供給網
- **場所**: `.github/workflows/deploy.yml:27,30,64`, `.github/workflows/ci.yml:14,16`
- **内容**: `actions/checkout@v4`, `aws-actions/configure-aws-credentials@v4`, `actions/upload-artifact@v4`, `ruby/setup-ruby@v1` はいずれも**可変 tag** 固定。リポジトリの `sha_pinning_required: false` (API 確認)。特に `deploy.yml` は `secrets.AWS_ACCESS_KEY_ID/SECRET/SSH_PRIVATE_KEY` を扱う (`deploy.yml:32-33,39`) ため、Action が乗っ取られ tag を書き換えられると**本番資格情報と SSH 秘密鍵を窃取**されうる。
- **攻撃シナリオ**: 上流 Action リポジトリ侵害 → `v4`/`v1` tag が悪意あるコミットへ移動 → 次回実行時に AWS 鍵・SSH 鍵を外部送信。
- **本番影響**: `configure-aws-credentials@v4` と SSH 鍵注入 step が同一 job にあるため被害集中。
- **推奨対策**: 全 Action を full-length commit SHA でピン留め (`uses: actions/checkout@<sha> # v4.x`)、Dependabot の actions ecosystem で更新追従、`sha_pinning_required` を有効化。
- **確認状況**: `ローカルで実証済み` (ファイル + API)。

### SEC-INF-11 依存関係の既知脆弱性と CI での依存監査欠如
- **深刻度**: Medium
- **種別**: 依存関係 / 供給網
- **場所**: `Gemfile.lock`, `package-lock.json`, `.github/workflows/ci.yml` (bundler-audit 等なし)
- **内容**: sengu の `Gemfile.lock` を GitHub Advisory DB に直接照合:
  - `rack 3.2.5`: **13 件** (fix 3.2.6)。multipart DoS (high) 数件、`Rack::Static` 系、Host/Forwarded ヘッダ系。ただし本アプリは `Rack::Static` 不使用・multipart 不使用 (JSON ボディのみ) で到達性は限定的。Host/Forwarded 系は host_authorization と併せ要注意。
  - `rack-session 2.1.1`: **1 件 critical** (GHSA-33qg-7wpp-89cq, fix 2.1.2)。ただしアプリはセッション/Cookie ミドルウェアを一切使っておらず (`grep` で `Rack::Session`/`enable :sessions` 0 件) **到達不能** → 実効影響ほぼ無し。
  - `puma 7.2.0`: 2 件 high (PROXY protocol v1)。PROXY protocol 未使用のため到達性低。
  - `sqlite3 2.9.1`: 2 件 low (UAF)。
  - Dependabot は open **79 件**と報告するが、その内訳は `mcp/package-lock.json` 44 件 + `Gemfile.lock` 32 件 (default branch = master 基準)。**MCP は sengu で撤去済** (`git ls-files mcp` = 0)、`nokogiri/activesupport/concurrent-ruby` 等の重い脆弱性群も**sengu の lock には存在しない** (master lock には 21 箇所)。つまり実際に稼働する sengu の攻撃面は master の Dependabot 表示より大幅に小さい。
  - npm: `esbuild 0.21.5` (dev-server SSRF GHSA-67mh-4wv8-2f99) はビルド専用 (`npm run build`) で `esbuild serve` 不使用 → 実効影響なし。`typescript 5.9.3`, `@types/node 26.6.1`。
  - **CI に依存監査ステップがない** (`bundler-audit`/`npm audit`/Dependabot 必須化なし)。`bundle install --deployment` で lock は凍結 (良), rubygems は HTTPS (良)。
- **攻撃シナリオ**: rack の multipart/Host 系は将来ミドルウェア追加時に顕在化。現状は到達性が低いものが中心。
- **本番影響**: 直近の実被害は小さいが、rack を 3.2.6 以降へ上げる価値は高い。
- **推奨対策**: `rack`→3.2.6+、`sqlite3`→最新、CI に `bundler-audit check --update` を追加 (nginx 検証と違い落とす)、Dependabot を sengu にも向ける。
- **確認状況**: `ローカルで実証済み` (Advisory DB 照合 + lock 差分)。

---

## Low

### SEC-INF-12 `smoke_test.sh` が旧ルートを叩き実 WABI ジョブを投入 (全面陳腐化)
- **深刻度**: Low
- **種別**: 設定不備 / 供給網 (運用)
- **場所**: `script/maintenance/smoke_test.sh:83-152`, `script/maintenance/README.md:33,50-62`
- **内容**: 新版に存在しないルートを前提: `/wabi_endpoint_status`, `/data/experiment_types`, `/data/sample_types`, `/data/chip_antigen`, `/qvalue_range`, `/data/search`, `/browse`, `/download`, `/colo?type=submit`, `/target_genes?type=submit`, `/wabi_chipatlas`。新ルートは `/api/*` `/jobs/submit` 等 (`routes/api.rb`, `routes/jobs.rb`) で、これら旧パスは**全滅**。さらに step 8 は `/wabi_chipatlas` へ実ジョブ POST を試みる。README は例として旧インスタンス IP `13.231.231.30` をハードコード。
- **攻撃シナリオ**: なし (自己テストの誤り)。新版に対して全 FAIL、監視として無意味・誤誘導。
- **本番影響**: 監視の空振り。`check_wabi.sh` は現行 WABI エンドポイント (`dtn1.ddbj.nig.ac.jp/wabi/chipatlas/`) に一致し正しいが、実ジョブを共有 SLURM に投入する点は運用上留意。
- **推奨対策**: smoke_test を新ルート (`/api/*`, `/jobs/available`, `/health`, `/status`) へ全面改訂、README の旧 IP 削除。
- **確認状況**: `ローカルで実証済み` (ルート定義との突合)。

### SEC-INF-13 CI の nginx 構文検証が実質 no-op (証明書欠如で常に失敗 → continue-on-error で隠蔽)
- **深刻度**: Low
- **種別**: 設定不備
- **場所**: `.github/workflows/ci.yml:85-92`, `config/nginx/chip-atlas.conf:16-17`
- **内容**: CI の nginx 検証は `continue-on-error: true` 付き。設定は `ssl_certificate /etc/letsencrypt/live/chip-atlas.org/fullchain.pem` を参照するが、CI ランナーに証明書は無い。ローカル再現で `nginx -t` は `cannot load certificate ... No such file` で**必ず失敗**する。continue-on-error がこれを飲み込むため、**構文チェックは事実上一度も成功しない = 検証していない**。同じ理由で provisioning の `sudo nginx -t && sudo systemctl reload nginx` (`deploy.sh:247`) も、証明書が無い新インスタンスでは失敗し `set -e` で中断する (AMI に証明書が焼かれている前提。Let's Encrypt は 90 日更新で静的 AMI と相性が悪く、更新経路が要確認)。
- **攻撃シナリオ**: なし。設定ミスを検出できないという保証の空洞化。
- **本番影響**: nginx 設定の退行を CI/デプロイで捕捉できない。
- **推奨対策**: CI は証明書パスをダミー化した設定でテストするか `nginx -t` をスタブ証明書付きで実行し `continue-on-error` を外す。AMI の証明書更新 (certbot systemd timer 等) を明文化。
- **確認状況**: `ローカルで実証済み` (`nginx -t` 再現)。

### SEC-INF-14 Dockerfile: root 実行 / HEALTHCHECK なし / .dockerignore の穴で巨大 DB・metadata を同梱
- **深刻度**: Low
- **種別**: 設定不備 / 情報漏洩 (イメージ層)
- **場所**: `Dockerfile:1-7`, `.dockerignore:1-18`, `docker-compose.dev.yml:4`
- **内容**: `Dockerfile` は `USER` 指定なし = **root 実行**、`bundle install` も root、`HEALTHCHECK` なし、`COPY . /app`。`.dockerignore` は `database.sqlite` (完全一致) は除くが `database.sqlite.latest` / `.rebuild` / `.verify` (各 ~620-680MB) と `metadata/` (1.5GB)・`rdf/`・`.superpowers/` を**除外していない** → ビルドコンテキスト ~3.6GB、ステイル DB とメタデータがイメージ層に焼き込まれる (削除しても層に残存)。逆に `database.sqlite` は除外されるため、この Dockerfile 単体で作るイメージには DB が無く `/health` が experiments 0 で 503 になる (docker-compose.yml はマウントもしない)。`docker-compose.dev.yml` は `ruby:3.3-slim` で、アプリ要件 4.0.5 (`.ruby-version`, `Dockerfile` base `ruby:4.0.5-slim`) と不一致。
- **攻撃シナリオ**: コンテナ侵害時に root で全 /app 操作可。イメージを共有すると層に古い DB/metadata が同梱され不要データ配布。
- **本番影響**: 本番は AMI+git+Puma 経路 (Docker 非依存) と読めるため実害限定。dev/配布用途で問題。
- **推奨対策**: `.dockerignore` に `database.sqlite*`・`metadata/`・`rdf/`・`.superpowers/` を追加、非 root `USER` 追加、`HEALTHCHECK` 追加、compose の Ruby を 4.0.5 に統一。
- **確認状況**: `ローカルで実証済み` (サイズ実測 + docker inspect)。

### SEC-INF-15 `/health` `/status` の外部公開・Puma worker_timeout と nginx タイムアウトの不整合
- **深刻度**: Low
- **種別**: 情報漏洩 / 設定不備
- **場所**: `routes/health.rb:8-40`, `config/nginx/chip-atlas.conf:56-65,74-76`, `config/puma.rb:24`
- **内容**: `/health` (`location = /health` で公開) は DB 状態 + experiments 件数、`/status` は各バックエンド (WABI/WES/data_server) の生死と機能可否を無認証で返す (本番 `curl https://chip-atlas.org/health` → 200 JSON を確認)。攻撃者に内部構成・依存の稼働状況を教える軽度な偵察面。また Puma `worker_timeout 60` に対し nginx `proxy_read_timeout 120s` で、60-120 秒かかる上流プロキシ (colo/target_genes の TSV 取得) は worker が先に殺され 502 になりうる。
- **攻撃シナリオ**: 偵察のみ。`/status` の機能可否から攻撃タイミングを計る程度。
- **本番影響**: 軽微。ALB ヘルスチェックに `/health` は必要なので完全非公開は不可 (SEC-INF-03 と両立設計が必要)。
- **推奨対策**: `/status` の詳細は最小化 or 内部限定、`/health` は ok/ng のみ、`worker_timeout` を nginx タイムアウト以上に。
- **確認状況**: `ローカルで実証済み` + 本番 GET。

---

## Info (参考・範囲外寄り)

- **旧インスタンスを terminate しない運用**: `deploy.sh:363-366` は「NOT terminated」と明示し手動 terminate を促すのみ。停止忘れ = コスト + 攻撃面 (旧コードの動く EC2 が残る)。運用ルールで担保を。
- **`check_wabi.sh`**: 実ジョブを DDBJ NIG スパコン (`dtn1.ddbj.nig.ac.jp`) の共有 SLURM に投入する (認証情報は無し)。監視として妥当だが共有資源消費に留意 (今回未実行)。
- **Sapporo/WES バックエンド (`script/sapporo-enrichment-analysis/`)**: `sapporo_config/run.sh` が `/var/run/docker.sock` をマウントし `eval ${cmd_txt}` で組み立てコマンドを実行、MinIO 資格情報を env 参照 (`${MINIO_ACCESS_KEY}` 等、値のハードコードなし)。ea.chip-atlas.org は現在 503 (awselb)。Web アプリ本体の範囲外だが、docker.sock 露出はホスト奪取に直結する設計なので当該ホストの隔離を推奨。
- **footer の mailto**: `views/_footer.erb:58` にキュレータの実メール (`okishinya@kumamoto-u.ac.jp`, cc `zou@kumamoto-u.ac.jp`)。本番でも露出、既に公開情報だが scraping 対象。情報のみ。
- **`.claude/scheduled_tasks.lock`** が tracked (`git ls-files .claude`)。sessionId + pid のみで機微性は低いが、開発者ローカル状態をリポジトリに含める必要はない。`.claude/settings.local.json` は tracked ではない (グローバル gitignore がカバー) — 良好。
- **secret scanning が無効** (public repo で API 確認)。将来の誤 commit を自動検出できない。有効化推奨。

---

## 問題なしと確認した項目 (監査済み・安全と判断)

- **ハードコード秘密情報なし**: 作業ツリー・git 全履歴 (1295 commit) を `AKIA[0-9A-Z]{16}` / `ASIA...` / 秘密鍵ブロック / `aws_secret`/`secret_access` で走査、実リテラル **0 件**。ヒット 2 件は `secrets.AWS_SECRET_ACCESS_KEY` (Actions 参照) と `AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}` (env 参照) のみ。弱パターン (`password`/`token`/`api_key`) のヒットも論文タイトル ("secretion" 等)・FTS の "token"・awk の "BEGIN" で、実秘密ではない。
- **`.gitignore` の主要カバレッジ**: `deploy.conf` / `launch-chip-atlas.conf` / `.env` / `database.sqlite*` / `log` / `metadata` / `tmp` はすべて ignore 済 (`git check-ignore -v` で確認)。`deploy.conf`・`launch-chip-atlas.conf` (非 example) は履歴に一度も commit されていない。**唯一の穴が `*_info.json` (SEC-INF-05)**。
- **`bundle install --deployment`** で lock 凍結 (`deploy.sh:237`)、rubygems は HTTPS。
- **`client_max_body_size 16m`** は実効 (17MB POST → 413 実証)。
- **TLS**: 新 nginx は `TLSv1.2 TLSv1.3` のみ (TLS1.1 は `alert protocol version` で拒否を実証)。本番も TLS1.0/1.1 無効 (`no protocols available`)、証明書は Amazon RSA 2048 (ALB 終端、2027-01 まで有効)。ただし `ssl_ciphers HIGH:!aNULL:!MD5` は非 PFS の RSA 鍵交換/CBC (AES256-SHA) も許容する (実証: AES256-SHA で 200)。PFS 強制 (ECDHE のみ) + `ssl_prefer_server_ciphers on` を推奨するが、深刻度は Low 未満のため本項に記載。
- **rack-protection 由来のヘッダ**: アプリ応答に `X-Frame-Options` / `X-Content-Type-Options` / `X-XSS-Protection` が付与される (実証)。session/cookie ミドルウェア不使用のため rack-session critical は到達不能。
- **`--dry-run`**: `validate_aws` と `get_current_instance` の read-only な AWS 呼び出しは走るが、launch/provision/register/deregister は全て `DRY_RUN` ガードで抑止 (`deploy.sh:165-169,193-196,221-224,272-275,304-307,348-351`)。読み取り専用として概ね正しい。
- **ALB ターゲット登録順序**: 新規を register→healthy 待ち→旧を deregister→drain (`deploy.sh:311-360`) の順で、blue-green として正しい (先に旧を落とさない)。
- **host_authorization (本番)**: `.chip-atlas.org` サブドメインのみ許可し、`evil.example.com` を 403 で拒否することを実証 (rack-protection HostAuthorization)。DNS リバインディング対策として機能。ただし ALB ヘルスチェックとの両立問題は SEC-INF-03 参照。
- **依存の大幅削減**: sengu で nokogiri/activerecord/activesupport/redcarpet/unicorn と MCP サーバ (hono 等 npm) が撤去され、master にあった脆弱性群 (21 箇所) が消滅。攻撃面は縮小方向。

## 未確認・不確実事項

1. **ALB の実リスナ/ターゲットグループ設定** (HTTP:80 か HTTPS:443 か、health check path/matcher、TLS 終端が ALB か nginx か)。SEC-INF-03 の実影響はこれ次第。AWS コンソール/CLI が必要 (本監査では AWS 操作禁止のため未実施)。
2. **本番 AMI の中身**: Let's Encrypt 証明書が焼き込まれているか、certbot 更新が動いているか、`unicorn.rb` が AMI 側に残っているか。SEC-INF-01/02/04/13 は「master にマージ後この deploy 経路を使ったら」の前提で、現行本番 (旧 master, Unicorn) はこのスクリプトと整合して動いている点に注意。
3. **`deploy.conf` の実値** (AWS account id / launch template / TG ARN)。gitignore 済で未取得。account_id は SEC-INF-05 の JSON と照合すれば判明しうるが未実施。
4. **git 履歴の filter-repo 要否**: `app-*_info.json` は既に公開履歴に残る。account/SG ID の機微性評価と履歴除去・KeyName ローテーションの要否はオーナー判断。
5. **本番の nginx 設定が config/nginx/chip-atlas.conf と一致するか**: 本番 `Server: nginx/1.18.0 (Ubuntu)` は旧 (`server_name _`) の可能性が高い。新設定の本番反映状況は未確認 (本番改変不可のため)。
6. **`/jobs/submit` の実レート**: limit_req 無しだが、上流 WABI/WES 側の受付制限は未検証 (外部サービスへの攻撃的リクエスト禁止のため)。
7. **Puma `before_fork` の DB 再接続**: `DB.disconnect` 後に各 worker が Sequel の遅延再接続で新コネクションを張る設計で、Sequel では正しい (ActiveRecord のような明示 reconnect 不要)。ローカル `/health` が全 worker で 200 を返すことは確認したが、本番 2 worker × 5 thread + WAL 下での競合は負荷試験未実施。
