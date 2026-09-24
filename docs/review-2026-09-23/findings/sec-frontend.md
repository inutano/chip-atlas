# SEC-FE: サーバレンダリング (ERB/kramdown) とブラウザ側コードの脆弱性監査

監査日: 2026-09-23 / 対象: `/Users/inutano/repos/chip-atlas` (sengu ブランチ、ローカル http://localhost:9292、コンテナ `chip-atlas-local` は `RACK_ENV=development`) / 比較対象: https://chip-atlas.org (GET のみ)

## 担当範囲の要約と総評

- **XSS (反射型・格納型・DOM 型) は見つからなかった。** 全 ERB は `set :erb, escape_html: true` (`app.rb:25`) の下で動き、`<%==` (生出力) は 62 箇所すべてを列挙して追跡した結果、リポジトリ固定文字列・アイコン partial・kramdown 出力・JSON island の 4 種類に限られ、params / DB / NCBI / WABI 由来の文字列が生出力に届く経路はない。TypeScript 側は `innerHTML` が空文字代入 3 箇所のみで、データは全て `textContent` / `createElement` / `URLSearchParams` / `encodeURIComponent` 経由。`eval` / `document.write` / `insertAdjacentHTML` / `postMessage` / `localStorage` は不使用。`/view?id=<script>`、`/search?q=<svg/onload=…>`、`/target_genes_result?track=<img …>`、`/enrichment_analysis_result?id=<script>`、`/nonexistent<script>` など 18 種のペイロードをローカルで送り、いずれも HTML に未エスケープで反射されないことを確認した。
- 本番 (旧版) と比べると、外部リンクの `rel="noopener noreferrer"` 付与、検索結果の HTML 非解釈 (旧版 DataTables は HTML として描画)、ジョブログの `textContent` 描画など、フロントエンドの安全性は明確に改善している。
- 一方で **保護ヘッダは本番と同一の 3 つ (`X-Frame-Options` / `X-Content-Type-Options` / `X-XSS-Protection`) のまま**で、CSP・HSTS・Referrer-Policy・Permissions-Policy がなく、nginx が直接配信する静的ファイルにはヘッダが一切付かない (SEC-FE-01)。
- Sinatra 既定の `Rack::Protection::HttpOrigin` は `reaction: :drop_session` によりセッション無しのこのアプリでは**無効** (クロスオリジン POST を 200 で受理することをローカルで実証)。現状 CSRF を防いでいるのは「JSON Content-Type 必須」という副次的な壁だけである (SEC-FE-02)。
- 残りは主にハードニング項目: 開発ビルドの source map (TS 全文入り) が配信される・deploy スクリプトがフロントエンドをビルドしない (SEC-FE-05)、public/ に残る 170 MB のレガシー JSON (SEC-FE-03)、`/view?id[]=` で 500 (SEC-FE-04)、検索 TSV の数式インジェクション (SEC-FE-06)、`/api/igv_url` の未検証パラメータ (SEC-FE-07)、JSON island の `<` 未エスケープ (SEC-FE-08)、`/publications` の毎回 kramdown 変換 (SEC-FE-09)。
- 深刻度内訳: Critical 0 / High 0 / Medium 1 / Low 8 / Info 7。

---

### SEC-FE-01 保護ヘッダの不足 (CSP / HSTS / Referrer-Policy / Permissions-Policy 未設定、静的配信はヘッダ無し)
- **深刻度**: Medium
- **種別**: 設定不備
- **場所**: `config/nginx/chip-atlas.conf:5-9` (80→301 のみ、HSTS 無し), `config/nginx/chip-atlas.conf:26-53` (静的 location に `add_header` はキャッシュ系のみ), `config/nginx/chip-atlas.conf:11-19` (`server_tokens` 未設定、`ssl_ciphers HIGH:!aNULL:!MD5`), `app.rb:24-27` (`set :protection` 未指定 = Sinatra 既定), `views/_navbar.erb:62-63` (インライン `onsubmit`), `views/_copy_code.erb:1-36` (インライン `<script>`), `views/colo_result.erb:26-43`, `views/target_genes_result.erb:44-49`, `views/enrichment_analysis.erb:119,121` (インライン `style=`)
- **内容**: ローカルと本番のヘッダを比較した結果 (curl -i):

  | パス | 新版 (localhost) | 本番 (chip-atlas.org) |
  |---|---|---|
  | HTML ページ (`/`, `/search`, `/view?id=…`, 404) | `x-frame-options: SAMEORIGIN`, `x-content-type-options: nosniff`, `x-xss-protection: 1; mode=block` | 同じ 3 つ + `server: nginx/1.18.0 (Ubuntu)`, `vary: Accept-Encoding` |
  | JSON API (`/api/*`, `/status`, `/health`) | `x-content-type-options: nosniff` のみ (+`cache-control: public` の一部) | `/data/genomes.json`: `nosniff` のみ |
  | 静的 (`/robots.txt`, css/js) | Sinatra 配信時は `nosniff` あり | nginx 直配信: `etag`/`last-modified` のみ、保護ヘッダ無し |
  | CSP / HSTS / Referrer-Policy / Permissions-Policy | 無し | 無し |

  この 3 ヘッダは Sinatra 既定の `Rack::Protection` (FrameOptions / XSSHeader) が HTML 応答に付けているもので、nginx が `try_files $uri` で直接返す `/css/`, `/js/`, `/images/`, `/robots.txt`, `/openapi.yaml` などには付かない (`config/nginx/chip-atlas.conf:26-53,79-81`)。`X-XSS-Protection: 1; mode=block` は廃止済みヘッダで、現行ブラウザは無視する (旧 Chrome の XSS Auditor では逆に情報漏洩に使われた経緯があり、推奨値は `0` か削除)。TLS 終端は nginx (`listen 443 ssl`, Let's Encrypt) だが HSTS が無いため、初回 http:// アクセスや手入力 URL に対して SSL ストリッピングが成立する。CSP が無いため、万一 XSS が入った場合の緩和層が無い。`server_tokens` 未設定のため本番同様 nginx のバージョンが露出する (本番は 1.18.0 = 2020 年リリースで EOL)。
- **攻撃シナリオ**: (1) 公衆 Wi-Fi 等で中間者が `http://chip-atlas.org/` への初回リクエストに応答し、偽の `/js/*.js` を注入 → 認証は無いが、IGV へ送るコマンド URL や解析結果リンクの改竄、フィッシングが可能。(2) 将来の XSS 混入時に CSP による封じ込めが効かない。(3) `X-Frame-Options` は nginx 直配信ファイルに付かないが HTML は Sinatra 経由なのでクリックジャッキング自体は防げている (問題なし)。
- **本番環境 (AWS EC2 + nginx + ALB) での実際の影響**: 本番も同じ 3 ヘッダのみで、新版で悪化はしていない。ALB は既定でセキュリティヘッダを追加しないため、nginx かアプリで付ける必要がある。認証・Cookie が無いので機密性への影響は小さく、主に完全性 (配信 JS/IGV コマンドの改竄) と多層防御の欠如。
- **推奨対策**:
  1. nginx 443 server ブロックに (location ごとの `add_header` は継承を打ち消すので snippet を `include` して各 location にも入れる):
     ```nginx
     server_tokens off;
     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
     add_header X-Content-Type-Options nosniff always;
     add_header X-Frame-Options SAMEORIGIN always;
     add_header Referrer-Policy strict-origin-when-cross-origin always;
     add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
     ```
  2. CSP (実装前提の変更込み)。JSON island (`type="application/json"`) は実行されないので CSP の対象外、`type="module"` の外部 JS と `bootstrap.bundle.min.js` は `'self'` で許可される。必要な変更は **(a)** `views/_navbar.erb:63` の `onsubmit` を外部 JS (全ページ共通の `/js/site.js` など) の `addEventListener` に移す、**(b)** `views/_copy_code.erb` の インライン `<script>` を `/js/copy-code.js` に移す (または `'sha256-…'` を許可)、**(c)** `colo_result.erb:26-43` / `target_genes_result.erb:44-49` / `enrichment_analysis.erb:119,121` の `style=` を CSS クラスに置換 (置換しないなら `style-src 'self' 'unsafe-inline'`)。JS からの `el.style.x = …` (CSSOM) と Popper の位置指定は `'unsafe-inline'` 無しで動く。
     ```
     Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self';
       img-src 'self' https://chip-atlas.dbcls.jp; connect-src 'self' http://localhost:60151;
       font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
     ```
     `connect-src` の `http://localhost:60151` は `frontend/components/igv.ts:31` の到達性プローブ用。まず `Content-Security-Policy-Report-Only` で導入して要ブラウザ確認。
  3. `X-XSS-Protection` は `set :protection, except: [:xss_header]` で外すか `0` にする。
- **確認状況**: ヘッダ比較は `ローカルで実証済み` (本番は GET で確認)。CSP 適合性は `要追加検証` (要ブラウザ確認)。

### SEC-FE-02 `Rack::Protection::HttpOrigin` が実質無効 (クロスオリジン POST を受理) — CSRF 防御が JSON Content-Type のみに依存
- **深刻度**: Low (現状は実害となる経路が無いが、将来の form 受理エンドポイントで即 CSRF になる潜在リスク)
- **種別**: 認可 / 設定不備 (CSRF)
- **場所**: `app.rb:24-27` (`set :protection` 未指定)、`sinatra-4.2.1/lib/sinatra/base.rb:1861-1875` (特に `:1873 options[:reaction] ||= :drop_session`)、`rack-protection-4.2.1/lib/rack/protection/http_origin.rb:23` (`default_reaction :deny` が上書きされる)、`rack-protection-4.2.1/lib/rack/protection/base.rb:56-58,102-105` (`drop_session` はセッションが無ければ何もしない)、`routes/pages.rb:101-110` (form POST を受ける唯一のルート)、`lib/middleware/json_body_parser.rb:17` (JSON 必須の実効的な壁)
- **内容**: Sinatra は既定で `Rack::Protection::HttpOrigin` を組み込むが、`reaction` を `:drop_session` に固定する。本アプリはセッションを使わないため `drop_session` は no-op となり、Origin が食い違う POST もそのまま通る。ローカルで実証:
  - `POST /jobs/estimated_time` + `Origin: https://evil.example` + JSON body → **200** `{"minutes":8}` (P21)
  - 同 `Origin: null` → **200** (P22)
  - `POST /enrichment_analysis` + `Origin: https://evil.example` + form body → **200** (P20)
  - 一方 `Rack::Protection::JsonCsrf` は `alias react deny` (`json_csrf.rb:24`) なので機能している: `GET /api/genomes` + `Referer: https://evil.example/` → **403** (P26)。

  現在、状態を変える POST (`/jobs/submit`, `/jobs/estimated_time`, `/api/igv_url`, `/api/download_url`) は `JsonBodyParser` が `application/json` の Content-Type を要求し (`text/plain` で送ると 400 `{"error":"No JSON body"}` — P23)、ブラウザから他オリジンへ JSON Content-Type で送るには CORS preflight が必要で本アプリは `Access-Control-Allow-*` を返さないため、CSRF は成立しない。form を受ける `POST /enrichment_analysis` はフォームの事前入力を返すだけで、被害者にできるのは「攻撃者が用意した遺伝子リストが入った投入画面を見せる」程度 (Info 相当)。
- **攻撃シナリオ**: 将来 `/jobs/submit` などが `application/x-www-form-urlencoded` も受けるようになった瞬間、攻撃者ページの自動送信フォームで被害者のブラウザから WABI ジョブを投入させられる (DDBJ の計算資源濫用、`title` に任意文字列)。現時点では JSON 必須が唯一の壁。
- **本番環境での実際の影響**: 旧版も Sinatra なので同様と推定 (未確認)。ALB/nginx は関与しない。
- **推奨対策**: `app.rb` に `set :protection, reaction: :deny` を追加すると HttpOrigin が 403 を返す (`IPSpoofing` も deny になるが `X-Client-IP` を使う経路は無いので影響なし)。nginx は `X-Forwarded-Proto` を渡しており (`chip-atlas.conf:73`)、`Rack::Request#scheme` がそれを読むので `base_url` は `https://chip-atlas.org` と一致する — ALB 経由の実環境で `Origin` 一致を要検証。あわせて `JsonBodyParser` の「JSON 以外は 400」を仕様として明文化し、form 受理を追加するときは CSRF トークンを必須にする。
- **確認状況**: `ローカルで実証済み` (P20/P21/P22/P23/P26) + gem ソースで機構を確認

### SEC-FE-03 public/ に残るレガシー大容量 JSON (44 MB / 170 MB) が無認証で配信される
- **深刻度**: Low (環境依存: ローカルには存在、本番デプロイに含まれるかは未確定)
- **種別**: DoS (帯域増幅) / 情報漏洩 (公開データのため機密性は無し)
- **場所**: `public/ExperimentList.json` (44,110,965 B)、`public/ExperimentList_adv.json` (170,745,570 B)、`public/analysisList.tab`、`public/tables/lineNum.tsv`、`public/icons/.gitkeep`、`config/nginx/chip-atlas.conf:21,79-81` (`root …/public; try_files $uri @app`)、`.gitignore` (`experimentList*json` を無視)、`.dockerignore` (Docker イメージからは除外)、`lib/tasks/metadata.rake:23-26` (現在の取込先は `metadata/`)
- **内容**: ローカルで `GET /ExperimentList.json` → 200 (44 MB)、`GET /ExperimentList_adv.json` → 200 (170 MB)、`GET /analysisList.tab` → 200 (`application/octet-stream`)、`GET /icons/.gitkeep` → 200。ブリーフの「`/data/*.json` 静的 JSON 配信は廃止」に反して、public/ に置かれた旧形式ファイルはそのまま配信される。新版のデータ取込は `metadata/` に落とすので、これらは作業中の残骸。
- **攻撃シナリオ**: `curl https://chip-atlas.org/ExperimentList_adv.json` を並列で叩くだけで 1 リクエスト 170 MB の送出。nginx 直配信で CPU 負荷は小さいが EC2 の帯域と転送課金を消費する。
- **本番環境での実際の影響**: git ベースのデプロイ (`script/deploy/deploy.sh:233-234`) では gitignore 済みなので配置されない見込みだが、手動コピーや過去の作業で残っていれば配信される。Docker では `.dockerignore` で除外済み。
- **推奨対策**: `public/ExperimentList*.json`, `public/analysisList.tab`, `public/tables/`, `public/icons/.gitkeep` を削除。nginx で `location ~ /\. { deny all; }` と `location ~* \.(json|tab|tsv)$ { … }` の明示的な許可リスト (`/diff-analysis.examples.json`, `/examples/` のみ) を検討。デプロイ後に `curl -I https://chip-atlas.org/ExperimentList_adv.json` が 404 であることをスモークテスト (`script/maintenance/smoke_test.sh`) に追加。
- **確認状況**: `ローカルで実証済み`、本番配置は `要追加検証`

### SEC-FE-04 `/view` の `id` が文字列以外だと 500 (型未検証)、開発モードではスタックトレースを返す
- **深刻度**: Low
- **種別**: DoS (軽微) / 情報漏洩 (開発モードのみ) / 入力検証
- **場所**: `routes/pages.rb:27-31` (`@expid = params[:id].upcase`)、`routes/pages.rb:33` (`redirect '/not_found', 404`)、`sinatra-4.2.1/lib/sinatra/base.rb:1943` (`show_exceptions` は development のみ)、`config/puma.rb:9` (既定 `RACK_ENV=production`)
- **内容**: `GET /view?id[]=a` → **500** `NoMethodError: undefined method 'upcase' for an instance of Array` (P5)。ローカルコンテナは `RACK_ENV=development` のため `Sinatra::ShowExceptions` が `text/plain` で完全なスタックトレース (`/app/routes/pages.rb:29`, `/tmp/bundle/ruby/4.0.0/gems/sinatra-4.2.1/...`) を返した。`/view?id=NOPE` は `redirect '/not_found', 404` により **404 + `Location: /not_found`** という奇妙な応答 (ブラウザは 404 の Location を追わず、`not_found` ハンドラが 404 ページ本文を描画するので実害は無いが意図と異なる)。`/view` (id 無し) は JSON の 400 (P6)。
- **攻撃シナリオ**: 500 を量産してログを埋める程度。開発モードでファイルパス・gem バージョン・Ruby バージョンが漏れる。
- **本番環境での実際の影響**: `config/puma.rb` の既定が production なので本番ではスタックトレースは出ず、Sinatra 既定の `<h1>Internal Server Error</h1>` になる (RACK_ENV を development にして起動しない限り)。
- **推奨対策**: `id = params[:id]; halt 400, json_response(error: 'id must be a string') unless id.is_a?(String) && id.match?(/\A[A-Za-z]{3}\d{5,}\z/)`。`redirect '/not_found', 404` は `halt 404, erb(:not_found)` に置換。本番起動手順で `RACK_ENV=production` を明示 (systemd unit 等) し、`/health` に環境名を出さない。
- **確認状況**: `ローカルで実証済み`

### SEC-FE-05 開発ビルドの source map (TypeScript 全文入り) が配信される / デプロイスクリプトがフロントエンドをビルドしない
- **深刻度**: Low
- **種別**: 情報漏洩 (軽微、OSS のため) / 供給網・設定不備 (デプロイ手順の不整合)
- **場所**: `esbuild.config.mjs:22-23` (`minify`/`sourcemap` は `NODE_ENV` 依存)、`.github/workflows/ci.yml:53` (`NODE_ENV=production npm run build` は CI のテスト用のみ)、`script/deploy/deploy.sh:230-260` (`git reset --hard origin/master` → `bundle install` → nginx 設定 → `rake` → **`unicorn`** 起動。`npm` / `NODE_ENV` の記述無し、`unicorn.rb` はリポジトリに存在しない)、`.gitignore` (`public/js/*.js`, `*.js.map` を無視)、`config/nginx/chip-atlas.conf:26-30` (`/js/` を直配信)、`public/js/*.js` (`//# sourceMappingURL=` 付き、未 minify)
- **内容**: ローカルの `public/js/*.js.map` 12 本すべてに `sourcesContent` が含まれ (frontend/**/*.ts の全文)、`GET /js/search.js.map` → 200 (28,895 B、`application/octet-stream`)。バンドル自体も未 minify で、内部コメント (「task C1」「D7」などの設計経緯、production との差異の説明) がそのまま読める。本番 (旧版) では `/js/search.js.map` → 404。TS は OSS で GitHub 公開なので機密性の問題ではないが、コード中のコメントは設計判断や既知の癖 (例: `enrichment-analysis.ts:414-435` のモチーフ推定の quirk) を含み、攻撃者の偵察を楽にする。
  より重要なのは、`public/js/*.js` が gitignore 済みなのに `deploy.sh` に Node ビルドが無く、しかも `unicorn` を起動する点: このスクリプトで新版をデプロイすると `/js/*.js` が存在せず (nginx `try_files` → アプリ 404) 全ページの JS が動かないか、開発機で作った未 minify + map 付きの成果物を手動コピーすることになる。
- **攻撃シナリオ**: `curl https://chip-atlas.org/js/experiment.js.map` で全 TS ソースとコメントを取得。
- **本番環境での実際の影響**: 新版の本番デプロイ手順が未確定 (ブリーフでも deploy pending)。どちらの経路でも map が混入し得る。
- **推奨対策**: (1) `deploy.sh` の provisioning に `npm ci && NODE_ENV=production npm run build` を追加 (Node が無いイメージなら CI でビルドした成果物をアーティファクトとして配布)、`unicorn` を `puma -C config/puma.rb` に置換。(2) nginx に `location ~ \.map$ { return 404; }`。(3) `esbuild.config.mjs` は本番既定を `sourcemap: false` にし、開発時のみ `--sourcemap` フラグで有効化。(4) `script/maintenance/smoke_test.sh` に `/js/*.js` が 200 かつ `/js/*.js.map` が 404 であることを追加。
- **確認状況**: map 配信は `ローカルで実証済み`、デプロイ経路は `コード上の推定`

### SEC-FE-06 検索結果の TSV ダウンロード / クリップボードコピーに数式インジェクション (CSV injection) 対策が無い
- **深刻度**: Low
- **種別**: Injection (スプレッドシート数式)
- **場所**: `frontend/pages/search.ts:192-202` (`toTsv`: 値をそのまま `\t` 連結)、`frontend/pages/search.ts:219-231` (`copyResultsToClipboard`)、`frontend/pages/search.ts:233-244` (`downloadTsv`)、データ源: `lib/models/experiment.rb:415-444` (`ExperimentList_adv.json` の `title`/`attributes` = SRA 投稿者の自由記述)
- **内容**: 検索結果の `title` / `attributes` は第三者 (SRA 投稿者) の自由記述で、`=`, `+`, `-`, `@` で始まる値や `\t`/`\n` を含む値をそのまま TSV に書き出す。ユーザーが Excel / LibreOffice で開くと数式として評価される (`=HYPERLINK(...)`, DDE `=cmd|'/C calc'!A0` など、警告ダイアログは出る)。同じ文字列は画面上では `textContent` なので無害。なお `/api/colo/download`, `/api/target_genes/download` は上流ファイルの素通し (routes/api.rb) で同じ性質だが本監査の範囲外。
- **攻撃シナリオ**: 悪意ある SRA 投稿者が属性に `=HYPERLINK("https://evil/x","open")` を含める → ChIP-Atlas 検索でヒットしたユーザーが TSV を保存し Excel で開く。
- **本番環境での実際の影響**: 旧版に TSV ダウンロード機能は無い (DataTables のコピー機能のみ) ため新版で新規に生じた経路。
- **推奨対策**: `toTsv` でセルごとに `if (/^[=+\-@\t\r]/.test(v)) v = "'" + v` (または先頭にタブ) を適用し、`\t`/`\n`/`\r` を空白に置換。ダウンロード名を `.tsv` から `.txt` にする手もある。
- **確認状況**: `コード上の推定` (DB 内に該当パターンの有無は未調査)

### SEC-FE-07 `/api/igv_url` がボディの `igv` をそのまま基底 URL に採用し、`genome` を検証せず URL に連結する
- **深刻度**: Low (自分宛の URL しか作れない)
- **種別**: 入力検証 / Open redirect 類似 (自己完結)
- **場所**: `lib/services/location_service.rb:22-31` (`igv = @data['igv'] || 'http://localhost:60151'`)、`routes/api.rb:133-142` (GET/POST)、`frontend/pages/peak-browser.ts:171-180` (`window.location.href = res.url`)、`frontend/components/genome-tabs.ts:8-10,26-30` (ハッシュの genome はレジストリで検証)
- **内容**: ローカルで実証:
  - `POST /api/igv_url` body `{"condition":{…},"igv":"javascript:alert(1)//"}` → `{"url":"javascript:alert(1)///load?genome=hg38&file=…"}` (P24)
  - `GET /api/igv_url?genome=hg38%26file%3Dhttp://evil/x.bed%23&…` → `{"url":"http://localhost:60151/load?genome=hg38&file=http://evil/x.bed#&file="}` (P25)

  フロントエンドは `igv` を送らず、`genome` はタブ (レジストリ検証済み) から来るので、被害者のブラウザにこの URL を踏ませる経路は無い (JSON POST は CORS preflight で他オリジンから撃てない)。API を直接使うエージェント/スクリプトが攻撃者の入力を素通しした場合のみ、`javascript:` URL や任意 `file=` の IGV コマンドを受け取る。
- **攻撃シナリオ**: LLM エージェントが利用者の指示に含まれる細工済み `genome` 値でこの API を呼び、返った URL をユーザーに提示 → ユーザーがクリックすると自分の IGV に `http://evil/x.bed` を読み込ませる。
- **本番環境での実際の影響**: 旧版にも `igv` オプションがあった経路 (`lib/pj/*.rb`) と推定 (未確認)。影響は限定的。
- **推奨対策**: `LocationService` で `@data['igv']` を無視するか `%r{\Ahttp://(localhost|127\.0\.0\.1)(:\d{1,5})?\z}` に制限。`genome` は `ChipAtlas::Experiment.genomes.key?` で検証し、それ以外は 400。`bed_url` が nil のときは `{url: null}` を返し `file=` 空を作らない。フロントエンドは `res.url` を `new URL()` で解析し `origin === 'http://localhost:60151'` のときだけ遷移する (現状 `igvOriginOf` は到達性プローブにしか使っていない)。
- **確認状況**: `ローカルで実証済み`

### SEC-FE-08 JSON island が `<` / `<!--` をエスケープしていない (`</` のみ) — `<!--<script` による HTML 飲み込み
- **深刻度**: Low (現状 DB に生の `<` は 0 件、POST 事前入力経由は自傷のみ)
- **種別**: XSS 周辺 / DoS (ページ破壊)
- **場所**: `views/experiment.erb:7`、`views/peak_browser.erb:6`、`views/colo.erb:6`、`views/target_genes.erb:6`、`views/diff_analysis.erb:6`、`views/enrichment_analysis.erb:6-14` (すべて `.to_json.gsub('</', '<\/')`)、`routes/pages.rb:101-110` (POST params を `prefill` に格納)
- **内容**: `</script>` は `<\/script>` に変換されるので script 要素の早期終了はできない (P19 で確認: `"genes":"<\/script><script>alert(1)<\/script><!--<script>"`)。ただし HTML 仕様のトークナイザは script 要素内の `<!--` + `<script` で "script data double escaped state" に入り、その状態では本来の `</script>` が終了タグとして扱われず、後続の HTML は `-->` が現れるまで script のテキストとして飲み込まれる。`experiment.erb:7` の island はページ先頭にあるため、`records` の `title`/`attributes` に `<!--<script` が含まれると `/view` ページの可視部分がすべて消え、`JSON.parse` も失敗して `experiment.ts` の初期化が止まる (実行はされないので XSS にはならない)。現状は上流メタデータが HTML entity 化済み (`&lt;` 等、SEC-FE-10 参照) で DB に生の `<` を含む行は 0 件 (`experiments` の title/attributes を LIKE で確認) のため到達不能。`enrichment_analysis.erb` の `prefill` は POST パラメータを直接入れるので到達可能だが、応答を見るのは POST した本人 (または SEC-FE-02 の経路で被害者に POST させた場合でも、壊れたページが表示されるだけ)。U+2028/2029 は `JSON.parse(textContent)` 経由なので問題無い。
- **攻撃シナリオ**: 上流 (SRA / ChIP-Atlas メタデータ生成) が entity 化をやめた場合、投稿者が属性に `<!--<script` を書くだけで当該実験の `/view` が真っ白になる。SEC-FE-10 の推奨 (取込時に entity をデコード) を実施するとこの経路が開くので、同時に対処が必要。
- **本番環境での実際の影響**: 現時点で無し。
- **推奨対策**: island 用ヘルパを 1 つ用意して全 6 箇所で使う:
  ```ruby
  def json_island(data)
    JSON.generate(data).gsub('<', '\\u003c').gsub('>', '\\u003e').gsub('&', '\\u0026')
  end
  ```
  (`JSON.generate(data, script_safe: true)` は `</` と U+2028/2029 のみで `<!--` を防げないため併用でも単独では不十分。)
- **確認状況**: `</` エスケープは `ローカルで実証済み`、`<!--<script` の飲み込みは `コード上の推定` (HTML 仕様のトークナイザ挙動、**要ブラウザ確認**)

### SEC-FE-09 `/publications` が毎リクエスト 300 KB の Markdown を kramdown で変換する (CPU 消費型 DoS の増幅点)
- **深刻度**: Low
- **種別**: DoS
- **場所**: `views/publications.erb:8`、`views/agents.erb:8`、`views/demo.erb:8`、`views/about.erb:119` (すべて `Kramdown::Document.new(File.read(...)).to_html` をテンプレート内で実行)、`config/puma.rb:12-17` (2 workers x 5 threads = 10 並列)
- **内容**: `views/publications.markdown` は 300,918 B。ローカルで `GET /publications` は 0.133-0.149 s (応答 351 KB)、`/agents` 0.006 s、`/` 0.020 s (`updates.markdown` は小さい)。本番 (旧版、Redcarpet 相当の `markdown` ヘルパ `old-app/views/publications.haml:29`) は 0.056-0.064 s。1 リクエストで 1 スレッドを約 140 ms 占有するため、単一クライアントの直列リクエストだけで約 7 req/s、10 並列で約 70 req/s に達するとアプリ全体が飽和する。ファイルはデプロイ時にしか変わらないので毎回の変換は無駄。
- **攻撃シナリオ**: `ab -c 20 -n 100000 https://chip-atlas.org/publications` 程度で全ページが遅延。ALB/nginx にレート制限は無い。
- **本番環境での実際の影響**: 旧版も毎回変換しており (処理は約半分の時間)、性質は同じ。
- **推奨対策**: 起動時に一度変換して定数化 (`configure do settings.set :publications_html, Kramdown::Document.new(...).to_html end`)、または `File.mtime` をキーにメモ化。応答に `Cache-Control: public, max-age=3600` を付け、nginx の `proxy_cache` で `/publications` をキャッシュ。
- **確認状況**: `ローカルで実証済み` (計測値)

### SEC-FE-10 上流メタデータが HTML entity 化済みのため二重エスケープされる (安全側だが表示劣化、本番と同一の癖)
- **深刻度**: Info
- **種別**: エスケープ設計 (機能上の劣化、セキュリティ上は安全側)
- **場所**: `lib/models/experiment.rb:294-336,415-444` (取込時に entity をデコードしない)、`views/experiment.erb:14,60,84` (`<%=` で再エスケープ)、`frontend/pages/search.ts:131-136` (`textContent` で entity 文字列をそのまま表示)
- **内容**: `database.sqlite.verify` を読み取り専用で集計: `experiments` の title/attributes/cell_type_subclass_info に `&amp;` を含む行 4,981、`&lt;`/`&gt;` を含む行 1,818、`experiments_fts` は 4,747 / 1,072。生の `<` を含む行は 0。つまり上流 (experimentList.tab / ExperimentList_adv.json) が HTML entity 化して配布している。結果:
  - `/view?id=SRX4639142`: DB 値 `Nuclear cycle &lt;=10` → HTML `Nuclear cycle &amp;lt;=10` → 画面では「Nuclear cycle &lt;=10」と表示 (ローカルで確認)。本番の `/view?id=SRX1614802` も `R&amp;amp;D Systems` (二重) で同じ癖。
  - `/api/search` は `R&amp;D Systems` を返し、新版の検索表は `textContent` なので「R&amp;D Systems」と表示。旧版の DataTables は `render` 未指定列を HTML として描画するため「R&D」と正しく見えていた (`old-app/public/js/pj/search.js:71-90` で確認) — 裏を返せば旧版は上流が生の HTML を混ぜれば格納型 XSS になる構造で、新版はそれを塞いだ代わりに entity が見えるようになった。
- **攻撃シナリオ**: 無し (安全側)。
- **本番環境での実際の影響**: `/view` は本番と同じ表示、検索表は本番より劣化 (機能面)。
- **推奨対策**: 取込 (`load_from_files` / `load_json_index`) で `CGI.unescapeHTML` を title / attributes / cell_type_subclass_info / FTS の title・attributes に適用し、DB は平文で持つ。これを行うと生の `<` が DB に入るので **SEC-FE-08 の island エスケープを同時に実施すること** (ERB の `<%=` と TS の `textContent` はそのままで安全)。
- **確認状況**: `ローカルで実証済み` (DB 集計と HTML 出力)

### SEC-FE-11 `Rack::Protection::JsonCsrf` が外部サイトからのリンク遷移で `/api/*` を 403 にする (UX)
- **深刻度**: Info
- **種別**: 設定 (可用性・互換性)
- **場所**: `rack-protection-4.2.1/lib/rack/protection/json_csrf.rb:24,39-44`、`app.rb:24-27`
- **内容**: JSON 応答に対し、`Origin` 無し・`Referer` のホストが自ホストと異なる GET を 403 にする。ローカルで `GET /api/genomes` + `Referer: https://evil.example/` → **403** (P26)。GitHub README や論文中のリンクから `https://chip-atlas.org/api/genomes` をクリックしたブラウザは `Referer: https://github.com/` を送るので 403 になる (エージェント/curl は Referer を送らないので影響無し)。`/agents` `/demo` は API URL を提示しており、この点で不整合。
- **推奨対策**: 本アプリは Cookie を使わず JSON hijacking の前提 (認証付き JSON) が無いので `set :protection, except: [:json_csrf]` で無効化してよい。無効化しない場合は `/agents` に注記。
- **確認状況**: `ローカルで実証済み`

### SEC-FE-12 平文 http:// への外部リンク、`mailto` 2 アドレスの露出
- **深刻度**: Info
- **種別**: 設定 / 情報漏洩 (軽微)
- **場所**: `views/peak_browser.erb:11` (`http://software.broadinstitute.org/...`), `views/peak_browser.erb:15`, `views/colo.erb:14`, `views/target_genes.erb:14`, `views/enrichment_analysis.erb:22` (`http://doi.org/10.7875/togotv...`), `frontend/pages/experiment.ts:178,183,185` (`http://pdbj.org`, `http://www.atcc.org`, `http://www2.brc.riken.jp`), `views/_footer.erb:58` (`mailto:okishinya@…?cc=zou@…`)
- **内容**: すべて `rel="noopener noreferrer"` 付き (TS 側は `item(..., {external:true})` が付与) なので Referer 漏洩と tabnabbing は無い。宛先が http:// なので経路上で改竄され得る (リンク先の責任だが https 化は可能: doi.org / pdbj.org / atcc.org / brc.riken.jp は https 対応)。`mailto` は本番と同一 (`chip-atlas.org` の footer で確認) で、スパム収集に晒される点は意図的な公開連絡先と判断。
- **推奨対策**: 上記を https:// に変更。`mailto` は現状維持で可 (連絡先の方針次第)。
- **確認状況**: `ローカルで実証済み` (ソース確認)

### SEC-FE-13 IGV 連携 (localhost:60151) に関する注記
- **深刻度**: Info
- **種別**: 設計上の注意点 (ChIP-Atlas 側で緩和不能な部分を含む)
- **場所**: `frontend/components/igv.ts:20-42` (`fetch('http://localhost:60151/echo', {mode:'no-cors'})`)、`frontend/pages/experiment.ts:14,80-112,271-292`、`frontend/pages/peak-browser.ts:166-185`、`lib/services/location_service.rb:22-31`
- **内容**: 送るのは `GET /load?file=<chip-atlas.dbcls.jp の URL>&genome=<DB 値>&name=<encodeURIComponent 済み DB 値>` と `/echo` プローブのみ。URL は定数プレフィックス + レジストリ検証済み genome + DB 由来値で組み立てられ、`wireIgvLinks` は `href.startsWith('http://localhost:60151')` の場合だけ横取りするので、外部データで別ホストへ向ける経路は無い。HTTPS ページからの `http://localhost` への fetch/遷移は Chrome/Firefox では "potentially trustworthy" として mixed content の対象外 (`igv.ts:16-18` のコメント通り)。Safari での挙動は **要ブラウザ確認** (機能面)。IGV のコマンドポート自体は任意のサイトからの `GET /load?file=…` を受け付ける設計で、これは IGV 側の問題であり ChIP-Atlas では緩和できない (CSP の `connect-src` に `http://localhost:60151` を入れる必要がある点は SEC-FE-01 に記載)。`window.location.href = res.url` で IGV の応答 ("OK") にページ遷移する挙動は本番と同じ。
- **推奨対策**: SEC-FE-07 の origin 検証を入れれば、サーバ側の不備があってもクライアントは localhost 以外へ遷移しない。
- **確認状況**: `コード上の推定` + `要ブラウザ確認`

### SEC-FE-14 エスケープ/XSS の回帰テストが無い
- **深刻度**: Info
- **種別**: テスト欠如
- **場所**: `test/routes/pages_test.rb` (`escape`/`<script` に関するアサーション無し、`:294` は page-data の JSON 解析のみ)、`test/routes/api_test.rb`
- **内容**: `escape_html` は 2026-05-14 に修正された経緯 (memory) があり、`<%=`/`<%==` の使い分けや island の `</` エスケープを守るテストが無いと再発を検出できない。
- **推奨対策**: `/view` で title/attributes に `<script>` を含む fixture を入れ `&lt;script&gt;` で出力されること、island に `</script>` が含まれないこと、`_page_header` の `lead` に params 由来の値が渡らないこと (grep ベース) をテスト化。
- **確認状況**: `コード上の推定`

### SEC-FE-15 `/api/remote_url_status` は許可ホストへの HEAD 中継 (ポート・パス自由)
- **深刻度**: Info (バックエンド監査と重複する可能性あり、フロントエンドから 3 回/ページ呼ばれるため記載)
- **種別**: SSRF (許可リスト付き)
- **場所**: `routes/api.rb:8-19,231-254`、`frontend/pages/experiment.ts:208-258`
- **内容**: `url` は `chip-atlas.dbcls.jp` / `dtn1.ddbj.nig.ac.jp` とそのサブドメインに限定されるが、ポートとパスは自由 (`https://chip-atlas.dbcls.jp:8443/…` や WABI のパスへ HEAD を送れる)。応答は `text/html` で 3 桁のステータスのみ (P27)。`http://localhost:9292/health` は 400 (P27)。公開ホストのみなので影響は小さいが、`cache_control :public, max_age: 3600` と組み合わさり、他人のプローブ結果をキャッシュ経由で共有する形になる。
- **推奨対策**: `uri.port` を 443 に固定、パスを `/data/` 配下に限定、または `/view` のサーバ側で 3 URL の存在確認を済ませ `@profiles` に `available: true/false` を載せてこの API 自体を廃止。
- **確認状況**: `ローカルで実証済み`

### SEC-FE-16 Markdown ページの信頼境界 (kramdown GFM、生 HTML 通過)
- **深刻度**: Info
- **種別**: 設計上の注記
- **場所**: `views/publications.erb:8`, `views/agents.erb:8`, `views/demo.erb:8`, `views/about.erb:119` (`Kramdown::Document.new(File.read(File.join(settings.views, '<name>.markdown')), input: 'GFM', hard_wrap: false).to_html`)、`views/updates.markdown:3` (HTML コメント内の `<span style="color:red">`)、`views/publications.markdown:1090,1152,1184` (`<i>`, `<sup>`)、`Gemfile.lock` (kramdown 2.5.2, kramdown-parser-gfm 1.1.0, rexml 3.4.4)
- **内容**: kramdown は既定で生 HTML を通す (`parse_block_html` 既定 false はブロック HTML 内を Markdown として解釈しないだけで、HTML 自体は出力される)。読み込むファイルは `settings.views` 配下の固定名でパス操作は不可能、内容はリポジトリ管理 (コミット権 = コード実行権なので信頼境界はリポジトリ)。4 ファイルとも `<script>`/`<iframe>`/`on*=`/`javascript:` を含まない (grep 確認)。kramdown 2.5.2 は CVE-2020-14001 (`{::options}` テンプレート RCE、2.3.0 修正) と CVE-2021-28834 (Rouge 経由の任意ファイル読取、2.3.1 修正) の影響を受けない。`_copy_code.erb` は `.markdown-content pre` の `textContent` をクリップボードに送るだけ。
- **推奨対策**: 現状で可。将来 Markdown を外部から取り込む場合は `Kramdown::Document.new(md, input: 'GFM', ...).to_html` の前に sanitize を挟むか `html_to_native` を無効化。
- **確認状況**: `ローカルで実証済み` (grep) + `コード上の推定`

---

## 問題なしと確認した項目 (監査済みで安全と判断したもの)

1. **`<%==` 全 62 箇所の棚卸し** (`grep -n '<%==' views/*.erb`): `erb :_icon` (name は固定文字列) 42 箇所、`erb :_page_header` 9 箇所 (`lead` は全呼び出しでリテラル、`about.erb:8-10` のみ `@number_of_experiments` を埋め込むが `formatted_experiment_count` は数字とカンマだけ)、`erb :_tutorial`/`_navbar`/`_footer`/`_copy_code`/`yield` 6 箇所、kramdown 4 箇所、JSON island 6 箇所 (`</` エスケープ済み、SEC-FE-08 参照)。params / DB / NCBI / WABI 由来の文字列が `<%==` に到達する経路は無い。
2. **`<%=` のエスケープ**: `views/experiment.erb:14,48-60,84,100,113,139-147,171-174,182,191` の DB 値・NCBI (`SraService`) 値・URL は Erubi の `escape_html` (`&<>"'` をエスケープ) を通る。`layout.erb:6,8` の `@page_description`/`@page_title` (= `@expid`, DB 存在確認済み) も同様。`_icon.erb` の `name`、`_tutorial.erb` の href は固定値。
3. **`@expid` / `params[:id]` の反射**: `id_valid?` (`lib/models/experiment.rb:194-196`) が DB 存在を要求するため、`/view` 本文に出る `@expid` は DB に実在する ID の upcase 形のみ。`/view?id=<script>` / `%22%3E%3Cimg…` / `GSM<script>` はすべて 404 ページ (P1/P2/P7)、404 ページはパスを echo しない (P16、`views/not_found.erb`)。`/api/*` の 404 は JSON (P17)。
4. **JSON API のエラーメッセージ**: `/api/colo/download?format=<script>` → `{"error":"Unknown format: <script>. …"}` は `application/json` + `nosniff` (P18)。`/jobs/<script>/status` は `[\w\-]+` 検証で 400 (P15、`routes/jobs.rb:10-14`)。`backend` は `wabi|wes`、`type` は 2 値の enum (`routes/jobs.rb:16-33`)。
5. **結果ページの URL パラメータ** (`frontend/components/result-page-params.ts:32-43`, `colo-result.ts:52-59`, `target-genes-result.ts:48-55`): `genome`/`track`/`cell_type`/`distance`/`id`/`backend`/`title`/`calcm` は `qs()` (`client.ts:230-235`, `encodeURIComponent`) で API URL にのみ使われ、DOM には `textContent` (`colo-result.ts:544`, `target-genes-result.ts:385,394`, `job-tracker.ts:294-295,909`) で出る。`emptyStateMessage` (`target-genes-result.ts:324-328`) も `textContent`。ローカルで `<img onerror>` を各パラメータに入れても HTML に反射しない (P10/P12/P14)。
6. **DOM シンク** (`public/js/*.js` を grep): `innerHTML` は `genome-tabs.ts:36`, `list-box.ts:39,47` の `= ''` のみ。`outerHTML`/`insertAdjacentHTML`/`document.write`/`eval`/`new Function`/`setAttribute('on…')`/`postMessage`/`localStorage`/`sessionStorage`/`document.cookie` は不使用。`.href =` は定数プレフィックス + `encodeURIComponent` (`search.ts:29-32,108`, `experiment.ts:50-63,80-112,162-192`, `colo-result.ts:413,469,536,539`, `target-genes-result.ts:264,380`) かサーバ生成 URL (`job-tracker.ts:149-161`: `ComputeRouter.result_urls` は定数 + 検証済み job_id、`experiment.ts:226,236,246`: `data-*` 属性はサーバの定数プレフィックス URL) のみ。`location.href` 遷移先は同一オリジンの相対パスか `res.url` (SEC-FE-07)。
7. **ジョブ状態・ログ**: `job-tracker.ts:173-184` (status は `textContent`、class は固定 3 値)、`:227-244` (ログは `<code>` の `textContent`)。`/jobs/:id/log` は `text/plain` + `nosniff`。
8. **オートコンプリート / ファセット / リストボックス** (`autocomplete.ts:88-103`, `facet-filter.ts:108-127`, `list-box.ts:46-70`): `textContent` と `option.value` のみ。
9. **ポップオーバー**: `info-popover.ts:37-42` は `html: false`、内容は定数 `HELP_TEXT`。Bootstrap 5.3.3 同梱 (`public/js/bootstrap.bundle.min.js:1-5`) で、私の知る範囲で 5.3.x に公開 XSS アドバイザリは無い (要確認)。
10. **`target="_blank"`**: ERB 内 14 箇所すべて `rel="noopener noreferrer"` (grep で未付与 0 件)。TS 側 (`job-tracker.ts:157-158`, `experiment.ts:58-59`, `search.ts:71-72,111-112`) も同様。本番の `/view` 外部リンクは `rel` 無し (`<a … target="_blank">` のみ) なので改善点。
11. **Referrer 漏洩**: 外部リンクは `noreferrer`、画像は同組織 (`chip-atlas.dbcls.jp`)、IGV への遷移は HTTPS→HTTP のため既定ポリシーで Referer 無し。URL に載る値はジョブ ID と解析タイトルのみ (WABI の結果は ID を知る全員が閲覧可能な設計、本番同様)。
12. **クリックジャッキング**: HTML 応答すべてに `X-Frame-Options: SAMEORIGIN` (Sinatra 経由)。JSON にも framing の価値は無い。
13. **Cookie / セッション**: `Set-Cookie` を返す応答無し。認証無し。
14. **CORS**: `Access-Control-Allow-Origin` を返さない → 他オリジンの JS から API を読めない (設計通り)。`JsonBodyParser` の JSON 必須と合わせ、ブラウザからのクロスオリジン状態変更は不可 (SEC-FE-02 の制限付き)。
15. **`host_authorization`**: 本番のみ `.chip-atlas.org` に制限 (`app.rb:66-68`)。
16. **静的資産の内容**: `public/icons/chip-atlas.svg` は `<symbol>`/`<path>` のみ (script/handler/foreignObject/外部 href 無し、`image/svg+xml` + `nosniff`)。`public/css/style.css` に `url()`/`@import`/`expression` 無し。バンドル・`llms.txt`・`openapi.yaml` にメールアドレス・鍵・トークン無し (`style.css` の "token" はコメントの語)。`robots.txt` は `/api`, `/view` 等を Disallow。
17. **ファイルアップロード** (`enrichment-analysis.ts:107-120`): `FileReader.readAsText` でテキストエリアに入れるだけ (クライアント側でのパース無し)。サイズ上限は無いが自分のブラウザにしか影響せず、送信時は nginx `client_max_body_size 16m` で制限。`countLines` (`:408-411`), `parseIds` (`diff-analysis.ts:104-106`), `genomeSpecies` (`:110-112`, 入力はレジストリ済み genome), `parseWabiSubmitTime`/`parseEstimateMinutes` (`job-tracker.ts:80-86,104-111`, アンカー付き固定長), `readGenomeFromHash` (`genome-tabs.ts:8-10`) はいずれも線形で ReDoS 無し。
18. **`/enrichment_analysis` の POST 事前入力**: `prefill` は JSON island → `textarea.value` / radio `checked` (`enrichment-analysis.ts:719-725`) で HTML 化されない (P19)。
19. **`Content-Disposition`** (`routes/api.rb:185,225`): `attachment` の filename は `File.basename` を通り、`track`/`cell_type` は上流にファイルが存在する値でないと 404 で到達しないため事実上固定 (`format` は enum)。
20. **依存バージョン** (`Gemfile.lock`): sinatra 4.2.1 / rack 3.2.5 / rack-protection 4.2.1 / erubi 1.13.1 / kramdown 2.5.2 / rexml 3.4.4 / puma 7.2.0 — 私の知る範囲で該当する未修正の公開脆弱性は無い。
21. **キャッシュヘッダ**: `cache_control :public` は genomes/stats/qval/bed_sizes/index 系と `/status` (30 s)、`/api/remote_url_status` のみ。個人データを含む応答は無く、`/api/search`, `/api/experiment`, `/jobs/*` にはキャッシュ指示が無いのでプライバシー上の懸念は無い。nginx の `expires 1d` は `asset_path` の `?v=mtime` (`app.rb:35-40`) で無効化される。

## 未確認・不確実事項

1. **ブラウザ実行が必要な確認 (要ブラウザ確認)**: (a) SEC-FE-08 の `<!--<script` による script 要素の飲み込みが実ブラウザで起きるか (HTML 仕様からの推定)。(b) SEC-FE-01 の CSP 案でページ・Bootstrap popover/dropdown・`blob:` ダウンロード (`search.ts:235-243`) が動くか (`Report-Only` で検証推奨)。(c) Safari が HTTPS ページから `http://localhost:60151` への `fetch(no-cors)` と遷移を許すか (SEC-FE-13)。(d) IGV への遷移後にページが "OK" 表示になる挙動 (本番同様と推定)。
2. **本番デプロイの実体**: 新版がどの手順で EC2 に配置されるか (`deploy.sh` は unicorn/npm 無しで旧構成)。source map・レガシー JSON・nginx ヘッダが本番でどうなるかはデプロイ後に `smoke_test.sh` で要確認。ALB がヘッダを追加しない前提で書いた。
3. **旧版のサーバ側設定**: 旧版 (`old-app/app.rb`) の `Rack::Protection` 設定や `/data/search` の実装は本監査では読んでいない (HttpOrigin 無効は「同様と推定」)。
4. **上流メタデータの entity 化が仕様か偶然か**: `experimentList.tab` / `ExperimentList_adv.json` の生成側 (chip-atlas.dbcls.jp) が今後も `&lt;` 形式を維持する保証は無い。SEC-FE-08 と SEC-FE-10 はこの前提に依存する。
5. **Bootstrap 5.3.3 / kramdown 2.5.2 の脆弱性状況**: 私の知識時点 (2026-06) の記憶に基づく判断で、最新のアドバイザリは未照合。
6. **DB 内の数式インジェクション該当値**: SEC-FE-06 について、`=`/`+`/`@` で始まる title/attributes の実在は未集計 (構造上の指摘)。
7. **ローカル固有の観測**: コンテナが `RACK_ENV=development` で動いているため、スタックトレース (SEC-FE-04) と source map (SEC-FE-05) はローカル固有の可能性がある。本番相当 (`RACK_ENV=production`, `NODE_ENV=production` ビルド) での再確認が必要。
8. **`/api/colo/download`, `/api/target_genes/download` の中身** (上流 TSV の素通し) と `/view` の NCBI eutils 呼び出しのレート制限は、バックエンド担当の範囲として深掘りしていない。
