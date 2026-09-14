# UI Parity with Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the rebuilt `sengu` UI look and behave as close to `https://chip-atlas.org` as possible, without reintroducing jQuery, DataTables, Font Awesome's CSS, or any CDN dependency.

**Architecture:** Three tiers, each independently shippable. Tier 1 is templates and CSS only — it restores the visual identity (icons, Bootstrap 3 component styling, type scale, container width). Tier 2 rewrites the two shared TypeScript components so they render `size="8"` list boxes and paired typeaheads, then rebuilds the analysis pages as numbered panel grids. Tier 3 restores two features the rebuild dropped: a default listing on Dataset Search and the Experiment Comparative Profile section.

**Tech Stack:** Sinatra + ERB (erubi, `escape_html: true`), Bootstrap 5.3.3 (vendored), plain CSS, TypeScript compiled by esbuild, minitest + rack-test. Ruby 4.0.5.

**Spec:** `docs/ui-parity-audit-2026-09-14.md` — read it first. Every exact colour, pixel value and icon name this plan refers to is tabulated there.

## Global Constraints

- **Zero external dependencies.** No CDN, no npm CSS, no webfont host. Everything self-hosted under `public/`.
- **Plain CSS and TypeScript only.** No CSS framework beyond the already-vendored Bootstrap 5, no new runtime libraries.
- **Target values come from Bootstrap 3.2.0**, not 3.3. Primary/link colour is `#428bca`, `.btn-primary` border `#357ebd`. The current `#337ab7` / `#2e6da4` in `public/css/style.css` is wrong and must be corrected.
- **Body type:** `"Helvetica Neue", Helvetica, Arial, sans-serif`, `14px`, line-height `1.42857143`, colour `#333`.
- **Container max-width:** `1170px` at ≥1200px viewport.
- **Templates escape by default.** `set :erb, escape_html: true` is active. Use `<%==` only for trusted server-generated HTML (partials, JSON islands). Never `<%==` a user-supplied value.
- **Every ERB change needs a page-render assertion** in `test/routes/pages_test.rb` (created in Task 1).
- **Every TypeScript change must pass** `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json` and `npm run build` before commit.
- **Font Awesome Free icons are CC BY 4.0.** The sprite file must carry an attribution comment.
- Run the full Ruby suite before each commit: **`bash script/dev/test.sh`** — referred to below as **`run-tests`**. It runs against the prebuilt `chip-atlas-test:local` image and completes in under a second. If the image is missing, build it once with `bash script/dev/build-test-image.sh`.
- Run the parity checklist after each task that changes markup: **`bash script/dev/ui-checklist.sh`** (Task 0). It prints a score; the score must never go down.
- Local instance for visual checks: `bash ~/run/chip-atlas-local.sh` → http://localhost:9292

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `test/routes/pages_test.rb` | Render assertions for all 11 HTML pages. The TDD harness for every template task. |
| `public/icons/chip-atlas.svg` | SVG sprite: 27 `<symbol>` elements, one per production glyph. |
| `views/_icon.erb` | Renders `<svg class="icon"><use href="/icons/chip-atlas.svg#NAME"/></svg>`. |
| `views/_page_header.erb` | The `h1` + mountain glyph + tagline + rule block shared by every page. |
| `frontend/components/list-box.ts` | `size="8"` list-box control with counts — the Flexselect replacement. |

**Modified**

| File | Change |
|---|---|
| `public/css/style.css` | Token corrections; Bootstrap 3 component styles (`.page-header`, `.jumbotron`, `.panel`, `.label`); icon sizing. |
| `views/layout.erb` | Container width class. |
| `views/_navbar.erb` | Icons, brand, two-row right cluster. |
| `views/about.erb` | Jumbotron-style feature cards with real glyphs. |
| `views/peak_browser.erb`, `enrichment_analysis.erb`, `diff_analysis.erb`, `target_genes.erb`, `colo.erb` | Numbered panel grids, Tutorial dropdowns, ⓘ buttons. |
| `views/experiment.erb` | Section icons; Comparative Profile section. |
| `views/search.erb` | Default listing and result counter. |
| `frontend/components/genome-tabs.ts` | Print species labels. |
| `frontend/components/facet-filter.ts` | List-box rendering mode. |
| `frontend/components/autocomplete.ts` | Paired list box below the input. |
| `frontend/pages/peak-browser.ts`, `enrichment-analysis.ts`, `diff-analysis.ts`, `target-genes.ts` | Wire the new panel layout. |
| `frontend/pages/search.ts` | Load first page on init. |
| `frontend/pages/experiment.ts` | Probe and reveal profile images. |
| `lib/services/location_service.rb` | Comparative Profile URL builders. |
| `routes/pages.rb` | Pass profile URLs to `experiment.erb`. |

---

# TIER 1 — CHROME

Templates and CSS only. No TypeScript logic changes. After Tier 1 the two apps read as the same site at a glance.

---

### Task 0: Parity evaluation harness

Nothing else in this plan can be measured without this. It produces the score every later task is judged against, and the contact sheets a human uses to judge what a score cannot capture.

**Files:**
- Create: `script/dev/ui-checklist.sh`
- Create: `script/dev/ui-parity.sh`
- Create: `script/dev/parity-markers.txt`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `bash script/dev/ui-checklist.sh` prints one line per marker and a final `SCORE: <passed>/<total>`, exiting 0 always (it is a metric, not a gate). Every later task re-runs it and records the new score.
- Produces: `bash script/dev/ui-parity.sh` writes side-by-side contact sheets to `tmp/ui-parity/<timestamp>/`.

- [ ] **Step 1: Write the marker list**

Each line is `PATH<TAB>DESCRIPTION<TAB>NEEDLE`. A marker passes when the local app's HTML for `PATH` contains `NEEDLE`. These are the structural facts the audit says production has and the rebuild lacks.

`script/dev/parity-markers.txt`:

```
/	navbar brand is the mountain glyph	chip-atlas.svg#mountain
/	navbar Peak Browser icon	chip-atlas.svg#glasses
/	navbar Enrichment Analysis icon	chip-atlas.svg#hand-holding-heart
/	navbar Diff Analysis icon	chip-atlas.svg#balance-scale-left
/	navbar Target Genes icon	chip-atlas.svg#bullseye
/	navbar Colo icon	chip-atlas.svg#compress-arrows-alt
/	navbar Publications icon	chip-atlas.svg#book
/	navbar Agents icon	chip-atlas.svg#robot
/	navbar Docs icon	chip-atlas.svg#github
/	navbar Search icon	chip-atlas.svg#search
/	container pinned to Bootstrap 3 width	container-narrow
/	page header rule	class="page-header"
/	homepage tiles are jumbotrons	class="jumbotron"
/	homepage tiles use Bootstrap 3 labels	class="label label-primary"
/peak_browser	panel 1 heading	1. Track type class
/peak_browser	panel 2 heading	2. Cell type Class
/peak_browser	panel 3 heading	3. Threshold for Significance
/peak_browser	optional track type panel	Track type (optional)
/peak_browser	optional cell type panel	Cell type (optional)
/peak_browser	Bootstrap 3 panels	class="panel panel-default"
/peak_browser	full download button label	Download BED file
/peak_browser	IGV help link	Error connecting to IGV?
/peak_browser	Tutorial dropdown	Tutorial
/enrichment_analysis	EA panel 1	1. Experiment type
/enrichment_analysis	EA panel 4	4. Enter dataset A
/enrichment_analysis	EA panel 5	5. Enter dataset B
/enrichment_analysis	EA panel 6	6. Analysis description
/enrichment_analysis	EA example link	Try with example
/enrichment_analysis	EA run-time estimate	Estimated run time
/target_genes	antigen list box container	id="antigen-list"
/target_genes	TSS distance labels	±1k
/search	result counter	id="search-count"
/view?id=SRX019491	experiment page title icon	chip-atlas.svg#file-alt
/view?id=SRX019491	comparative profile section	Experiment Comparative Profile
/view?id=SRX019491	distribution image	distribution/png/
```

- [ ] **Step 2: Write the checklist script**

`script/dev/ui-checklist.sh`:

```bash
#!/usr/bin/env bash
# UI parity checklist: how many production structural markers the local app has.
# Usage: bash script/dev/ui-checklist.sh [BASE_URL]
# Always exits 0 - this is a metric, not a gate.
set -uo pipefail
BASE="${1:-http://localhost:9292}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKERS="$DIR/parity-markers.txt"

if ! curl -sf -o /dev/null -m 5 "$BASE/health"; then
  echo "App not reachable at $BASE - start it with: bash ~/run/chip-atlas-local.sh"
  exit 0
fi

pass=0; total=0; cache_path=""; cache_body=""
while IFS=$'\t' read -r path desc needle; do
  [ -z "${path:-}" ] && continue
  case "$path" in \#*) continue ;; esac
  total=$((total + 1))
  if [ "$path" != "$cache_path" ]; then
    cache_body="$(curl -s -m 20 "$BASE$path")"
    cache_path="$path"
  fi
  if printf '%s' "$cache_body" | grep -qF -- "$needle"; then
    pass=$((pass + 1)); printf '  PASS  %-45s %s\n' "$desc" "$path"
  else
    printf '  FAIL  %-45s %s\n' "$desc" "$path"
  fi
done < "$MARKERS"

echo
echo "SCORE: $pass/$total"
exit 0
```

- [ ] **Step 3: Run it to capture the baseline**

Run: `bash script/dev/ui-checklist.sh`
Expected: a low score (most markers FAIL — that is the point). **Record the exact baseline number in the commit message**; every later task must raise it or hold it.

- [ ] **Step 4: Write the contact-sheet script**

`script/dev/ui-parity.sh`:

```bash
#!/usr/bin/env bash
# Side-by-side screenshots of production vs the local app.
# Usage: bash script/dev/ui-parity.sh [BASE_URL]
set -euo pipefail
BASE="${1:-http://localhost:9292}"
OLD="https://chip-atlas.org"
OUT="tmp/ui-parity/$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$OUT"

PAGES="/ /peak_browser /search /colo /target_genes /enrichment_analysis /diff_analysis"
VIEW="/view?id=SRX019491"

shoot () { # url outfile
  chromium --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --window-size=1440,1600 --virtual-time-budget=10000 \
    --screenshot="$2" "$1" >/dev/null 2>&1 || true
}

for p in $PAGES "$VIEW"; do
  name="$(printf '%s' "$p" | tr -c 'A-Za-z0-9' '_')"
  shoot "$OLD$p"  "$OUT/${name}_old.png"
  shoot "$BASE$p" "$OUT/${name}_new.png"
  if [ -f "$OUT/${name}_old.png" ] && [ -f "$OUT/${name}_new.png" ]; then
    magick "$OUT/${name}_old.png" "$OUT/${name}_new.png" +append "$OUT/${name}_sheet.png"
    rm -f "$OUT/${name}_old.png" "$OUT/${name}_new.png"
    echo "  $OUT/${name}_sheet.png"
  fi
done

echo "Contact sheets in $OUT (left = production, right = local)"
```

- [ ] **Step 5: Ignore the output directory**

`tmp` is already in `.gitignore` — confirm with `grep -n '^tmp$' .gitignore`. If it is absent, add it.

- [ ] **Step 6: Make both scripts executable and run them**

```bash
chmod +x script/dev/ui-checklist.sh script/dev/ui-parity.sh
bash script/dev/ui-checklist.sh
bash script/dev/ui-parity.sh
```

Expected: a score line, and one contact sheet per page. Open one and confirm production is on the left, local on the right.

- [ ] **Step 7: Commit**

```bash
git add script/dev/ .gitignore
git commit -m "Add UI parity evaluation harness (checklist score + contact sheets)"
```

---

### Task 1: Page-render test harness

Without this there is no way to assert on template output, and every later task in Tier 1 is untested. Build it first.

**Files:**
- Create: `test/routes/pages_test.rb`

**Interfaces:**
- Produces: a `PagesTest` class using `Rack::Test::Methods` against `ChipAtlasApp`. Later tasks add assertions to it.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require 'test_helper'

class PagesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    ChipAtlasApp
  end

  PAGES = %w[
    / /peak_browser /search /colo /target_genes
    /enrichment_analysis /diff_analysis /publications /agents /demo
  ].freeze

  def test_all_pages_render_ok
    PAGES.each do |path|
      get path
      assert_equal 200, last_response.status, "#{path} did not return 200"
      assert_includes last_response.body, '<nav', "#{path} has no navbar"
      assert_includes last_response.body, '</html>', "#{path} is truncated"
    end
  end

  def test_layout_uses_fixed_width_container
    get '/'
    assert_includes last_response.body, 'class="container container-narrow"'
  end
end
```

- [ ] **Step 2: Run it to confirm the container assertion fails**

Run: `run-tests`
Expected: `test_all_pages_render_ok` PASSES, `test_layout_uses_fixed_width_container` FAILS — the layout currently emits plain `class="container"`.

- [ ] **Step 3: Add the container class**

In `views/layout.erb`, change:

```erb
  <div class="container">
```

to:

```erb
  <div class="container container-narrow">
```

- [ ] **Step 4: Add the width rule**

Append to `public/css/style.css`:

```css
/* ===== Layout: match Bootstrap 3 container widths ===== */
@media (min-width: 1200px) {
  .container-narrow {
    max-width: 1170px;
  }
}
```

- [ ] **Step 5: Run tests**

Run: `run-tests`
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add test/routes/pages_test.rb views/layout.erb public/css/style.css
git commit -m "Add page render tests and pin container to Bootstrap 3 width"
```

---

### Task 2: Design tokens

Correct the four wrong values before any component work, so everything built afterwards inherits the right base.

**Files:**
- Modify: `public/css/style.css:1-20`
- Test: `test/routes/pages_test.rb`

**Interfaces:**
- Produces: CSS custom properties every later task relies on. `--ca-primary: #428bca`, `--ca-primary-dark: #357ebd`.

- [ ] **Step 1: Write the failing test**

Add to `test/routes/pages_test.rb`:

```ruby
  def test_stylesheet_uses_bootstrap3_primary
    css = File.read(File.join(__dir__, '..', '..', 'public', 'css', 'style.css'))
    assert_includes css, '#428bca', 'primary colour must match Bootstrap 3.2'
    refute_includes css, '#337ab7', 'Bootstrap 3.3 primary must not be used'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — `#337ab7` is still present.

- [ ] **Step 3: Replace the token block**

In `public/css/style.css`, replace the whole `/* ===== Colors ===== */` block and the `.btn-primary` block that follows it with:

```css
/* ===== Design tokens — Bootstrap 3.2.0 values from production ===== */
:root {
  --ca-primary: #428bca;
  --ca-primary-dark: #357ebd;
  --ca-navbar-bg: #222;
  --ca-navbar-active: #080808;
  --ca-panel-head: #f5f5f5;
  --ca-panel-border: #ddd;
  --ca-jumbotron-bg: #eee;
  --ca-rule: #eee;

  --bs-primary: #428bca;
  --bs-primary-rgb: 66, 139, 202;
  --bs-link-color: #428bca;
  --bs-link-color-rgb: 66, 139, 202;
  --bs-link-hover-color: #2a6496;
  --bs-font-sans-serif: "Helvetica Neue", Helvetica, Arial, sans-serif;
  --bs-body-font-size: 14px;
  --bs-body-line-height: 1.42857143;
  --bs-body-color: #333;
}

.btn-primary {
  --bs-btn-bg: var(--ca-primary);
  --bs-btn-border-color: var(--ca-primary-dark);
  --bs-btn-hover-bg: #3276b1;
  --bs-btn-hover-border-color: #285e8e;
}

.navbar.bg-dark {
  background-color: var(--ca-navbar-bg) !important;
}

.navbar-dark .navbar-nav .nav-link.active {
  background-color: var(--ca-navbar-active);
  color: #fff;
}
```

- [ ] **Step 4: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 5: Visual check**

Reload http://localhost:9292 and confirm body text is smaller (14px), links are the lighter `#428bca` blue, and the navbar is `#222` rather than `#212529`.

- [ ] **Step 6: Commit**

```bash
git add public/css/style.css test/routes/pages_test.rb
git commit -m "Correct design tokens to Bootstrap 3.2 values"
```

---

### Task 3: Icon sprite and partial

**Files:**
- Create: `public/icons/chip-atlas.svg`
- Create: `views/_icon.erb`
- Modify: `public/css/style.css`
- Modify: `.gitignore` (ensure `public/icons/chip-atlas.svg` is tracked)
- Test: `test/routes/pages_test.rb`

**Interfaces:**
- Produces: `erb :_icon, locals: { name: 'mountain' }` → `<svg class="icon" aria-hidden="true"><use href="/icons/chip-atlas.svg#mountain"></use></svg>`. Every later task uses this call shape. Symbol ids are the Font Awesome names with the `fa-` prefix stripped: `mountain`, `glasses`, `hand-holding-heart`, `balance-scale-left`, `bullseye`, `compress-arrows-alt`, `book`, `robot`, `github`, `search`, `info-circle`, `question-circle`, `spinner`, `download`, `dna`, `chart-line`, `chart-bar`, `project-diagram`, `external-link-alt`, `user-edit`, `tag`, `server`, `microscope`, `flask`, `file-alt`, `eye`, `cogs`.

- [ ] **Step 1: Write the failing test**

Add to `test/routes/pages_test.rb`:

```ruby
  SPRITE_SYMBOLS = %w[
    mountain glasses hand-holding-heart balance-scale-left bullseye
    compress-arrows-alt book robot github search info-circle question-circle
    spinner download dna chart-line chart-bar project-diagram
    external-link-alt user-edit tag server microscope flask file-alt eye cogs
  ].freeze

  def test_sprite_defines_every_symbol
    sprite = File.read(File.join(__dir__, '..', '..', 'public', 'icons', 'chip-atlas.svg'))
    SPRITE_SYMBOLS.each do |name|
      assert_includes sprite, %(id="#{name}"), "sprite is missing symbol #{name}"
    end
  end

  def test_sprite_is_served
    get '/icons/chip-atlas.svg'
    assert_equal 200, last_response.status
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL with `Errno::ENOENT` — the sprite does not exist.

- [ ] **Step 3: Build the sprite**

Download the Font Awesome 5 Free SVG for each name from the `@fortawesome/fontawesome-free` package's `svgs/solid/` (and `svgs/brands/github.svg`), then assemble one file. Each `<symbol>` keeps the source `viewBox` — Font Awesome viewBoxes differ per glyph, so do **not** normalise them.

`public/icons/chip-atlas.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" style="display:none">
  <!--
    Icon paths from Font Awesome Free 5 (https://fontawesome.com).
    Icons licensed CC BY 4.0. Vendored subset - no CDN, no runtime dependency.
  -->
  <symbol id="mountain" viewBox="0 0 640 512"><path d="M634.92 462.7l-288-448C341.03 5.54 330.89 0 320 0s-21.03 5.54-26.92 14.7l-288 448a32.001 32.001 0 0 0-1.17 32.64A32.004 32.004 0 0 0 32 512h576c11.71 0 22.48-6.39 28.09-16.66a32.001 32.001 0 0 0-1.17-32.64zM320 91.18L405.39 224H320l-64 64-32-32-27.94 27.94L320 91.18z"/></symbol>
  <!-- ... one <symbol> per name in SPRITE_SYMBOLS ... -->
</svg>
```

Verify every symbol is present before moving on:

```bash
for n in mountain glasses hand-holding-heart balance-scale-left bullseye \
         compress-arrows-alt book robot github search info-circle question-circle \
         spinner download dna chart-line chart-bar project-diagram \
         external-link-alt user-edit tag server microscope flask file-alt eye cogs; do
  grep -q "id=\"$n\"" public/icons/chip-atlas.svg || echo "MISSING: $n"
done
```

- [ ] **Step 4: Write the partial**

`views/_icon.erb`:

```erb
<svg class="icon<%= " icon-#{size}" if defined?(size) && size %>" aria-hidden="true" focusable="false"><use href="/icons/chip-atlas.svg#<%= name %>"></use></svg>
```

- [ ] **Step 5: Add icon CSS**

Append to `public/css/style.css`:

```css
/* ===== Icons ===== */
.icon {
  display: inline-block;
  width: 1em;
  height: 1em;
  fill: currentColor;
  vertical-align: -0.125em;
}

.icon-lg { width: 70px; height: 70px; vertical-align: middle; }

.navbar .nav-link .icon,
.navbar .navbar-brand .icon { margin-right: 5px; }

h1 .icon, h3 .icon, h4 .icon { margin-right: 8px; }
```

- [ ] **Step 6: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add public/icons/chip-atlas.svg views/_icon.erb public/css/style.css test/routes/pages_test.rb
git commit -m "Vendor Font Awesome subset as an SVG sprite with an icon partial"
```

---

### Task 4: Navbar icons, brand and two-row layout

**Files:**
- Modify: `views/_navbar.erb`
- Modify: `public/css/style.css`
- Test: `test/routes/pages_test.rb`

**Interfaces:**
- Consumes: `erb :_icon, locals: { name: ... }` from Task 3.

- [ ] **Step 1: Write the failing test**

Add to `test/routes/pages_test.rb`:

```ruby
  NAV_ICONS = {
    'peak_browser'        => 'glasses',
    'enrichment_analysis' => 'hand-holding-heart',
    'diff_analysis'       => 'balance-scale-left',
    'target_genes'        => 'bullseye',
    'colo'                => 'compress-arrows-alt',
    'publications'        => 'book',
    'agents'              => 'robot'
  }.freeze

  def test_navbar_links_carry_their_icons
    get '/'
    body = last_response.body
    NAV_ICONS.each_value do |icon|
      assert_includes body, "chip-atlas.svg##{icon}", "navbar is missing the #{icon} icon"
    end
    assert_includes body, 'chip-atlas.svg#github'
    assert_includes body, 'chip-atlas.svg#search'
  end

  def test_navbar_brand_is_the_mountain
    get '/'
    assert_includes last_response.body, 'chip-atlas.svg#mountain'
    refute_includes last_response.body, 'M8 1l2 5h5l-4 3 1.5 5L8 11 3.5 14 5 9 1 6h5z'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — no sprite references in the navbar, and the star path is still there.

- [ ] **Step 3: Replace the brand**

In `views/_navbar.erb`, replace the entire inline `<svg>` inside `.navbar-brand` with:

```erb
      <%== erb :_icon, locals: { name: 'mountain' } %>
```

- [ ] **Step 4: Add an icon to every nav link**

For each `<li class="nav-item">`, insert the partial immediately before the `<span class="full-text">`. Peak Browser becomes:

```erb
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'peak_browser' %>" href="/peak_browser">
            <%== erb :_icon, locals: { name: 'glasses' } %>
            <span class="full-text">Peak Browser</span>
            <span class="abbrev-text">PB</span>
          </a>
        </li>
```

Repeat with: `hand-holding-heart` (Enrichment Analysis), `balance-scale-left` (Diff Analysis), `bullseye` (Target Genes), `compress-arrows-alt` (Colo), `book` (Publications), `robot` (Agents), `github` (Docs). Give **Demo** no icon — production has no Demo item, so there is no glyph to match; leaving it bare keeps it visually secondary pending the open question about whether it ships.

Touch only the `<ul class="navbar-nav">` links here. The Search link lives in the right cluster and is handled in Step 5 — do not add an icon to it in this step, or you will end up with two Search links.

- [ ] **Step 5: Move the ID field to a second row**

Replace the `<div class="d-flex align-items-center">` wrapper and everything inside it with:

```erb
      <div class="navbar-right-stack">
        <a class="nav-link text-light" href="/search">
          <%== erb :_icon, locals: { name: 'search' } %>
          <span class="full-text">Search</span>
          <span class="abbrev-text">?</span>
        </a>
        <form class="navbar-id-form" role="search"
              onsubmit="event.preventDefault(); window.open('/view?id=' + encodeURIComponent(document.getElementById('jumpToExperiment').value));">
          <span class="text-light me-2">ID:</span>
          <input class="form-control form-control-sm me-2" type="text" id="jumpToExperiment"
                 value="SRX018625" aria-label="Experiment ID">
          <button class="btn btn-light btn-sm" type="submit">Go</button>
        </form>
      </div>
```

Append to `public/css/style.css`:

```css
/* ===== Navbar right cluster: Search on row 1, ID form on row 2 ===== */
.navbar-right-stack {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

.navbar-id-form {
  display: flex;
  align-items: center;
}

@media (max-width: 991.98px) {
  .navbar-right-stack {
    align-items: flex-start;
    margin-top: 8px;
  }
}
```

- [ ] **Step 6: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 7: Visual check against production**

```bash
chromium --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --window-size=1440,120 --virtual-time-budget=9000 \
  --screenshot=/tmp/nav_check.png http://localhost:9292/
```

Compare against `docs/ui-parity-audit-2026-09-14.md`. The icon row and the ID field's second row should line up with production.

- [ ] **Step 8: Commit**

```bash
git add views/_navbar.erb public/css/style.css test/routes/pages_test.rb
git commit -m "Restore navbar icons, mountain brand and two-row ID field"
```

---

### Task 5: Page header partial

**Files:**
- Create: `views/_page_header.erb`
- Modify: `views/about.erb`, `peak_browser.erb`, `search.erb`, `colo.erb`, `target_genes.erb`, `enrichment_analysis.erb`, `diff_analysis.erb`
- Modify: `public/css/style.css`
- Test: `test/routes/pages_test.rb`

**Interfaces:**
- Produces: `erb :_page_header, locals: { title: 'ChIP-Atlas: Peak Browser', lead: '...' }`. `lead` may contain trusted HTML (links) and is emitted with `<%==`; never pass user input to it.

- [ ] **Step 1: Write the failing test**

```ruby
  def test_pages_have_a_page_header_with_the_mountain
    %w[/ /peak_browser /search /colo /target_genes
       /enrichment_analysis /diff_analysis].each do |path|
      get path
      assert_includes last_response.body, 'class="page-header"', "#{path} has no page header"
      assert_includes last_response.body, 'chip-atlas.svg#mountain', "#{path} h1 has no mountain"
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL on `/` — no `.page-header` class is emitted anywhere.

- [ ] **Step 3: Write the partial**

`views/_page_header.erb`:

```erb
<div class="page-header">
  <h1>
    <%== erb :_icon, locals: { name: 'mountain' } %>
    <%= title %>
  </h1>
  <% if defined?(lead) && lead %>
    <p class="main-desc"><%== lead %></p>
  <% end %>
</div>
```

- [ ] **Step 4: Add the Bootstrap 3 rule**

Append to `public/css/style.css`:

```css
/* ===== Page header (Bootstrap 3 .page-header, dropped in BS5) ===== */
.page-header {
  padding-bottom: 9px;
  margin: 40px 0 20px;
  border-bottom: 1px solid var(--ca-rule);
}

.page-header h1 {
  margin-top: 0;
  letter-spacing: -1px;
}

.page-header .main-desc {
  line-height: 150%;
  margin-bottom: 0;
}
```

- [ ] **Step 5: Use it on every page**

In `views/about.erb`, replace the `<div class="page-header mb-4">…</div>` block with:

```erb
<%== erb :_page_header, locals: {
  title: 'ChIP-Atlas',
  lead: "A data-mining suite for exploring epigenomic landscapes by fully integrating " \
        "<span id=\"experiment-count\">#{@number_of_experiments}</span> " \
        "ChIP-seq, ATAC-seq and Bisulfite-seq experiments."
} %>
```

In `views/peak_browser.erb`, replace the `<div class="row mb-3">…</div>` title block with:

```erb
<%== erb :_page_header, locals: {
  title: 'ChIP-Atlas: Peak Browser',
  lead: 'Visualize TF-binding, histone marks, chromatin accessibility, and DNA methylation on ' \
        '<a href="http://software.broadinstitute.org/software/igv/home" target="_blank" rel="noopener noreferrer">IGV</a>'
} %>
```

Apply the same replacement in `search.erb`, `colo.erb`, `target_genes.erb`, `enrichment_analysis.erb` and `diff_analysis.erb`, keeping each page's existing title and lead text verbatim.

- [ ] **Step 6: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add views/_page_header.erb views/*.erb public/css/style.css test/routes/pages_test.rb
git commit -m "Add shared page header partial with mountain glyph and rule"
```

---

### Task 6: Homepage feature cards

**Files:**
- Modify: `views/about.erb`
- Modify: `public/css/style.css`
- Test: `test/routes/pages_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  FEATURE_ICONS = {
    '/peak_browser'        => 'glasses',
    '/enrichment_analysis' => 'hand-holding-heart',
    '/diff_analysis'       => 'balance-scale-left',
    '/target_genes'        => 'bullseye',
    '/colo'                => 'compress-arrows-alt',
    '/search'              => 'search'
  }.freeze

  def test_homepage_cards_use_glyphs_not_emoji
    get '/'
    body = last_response.body
    FEATURE_ICONS.each_value do |icon|
      assert_includes body, "chip-atlas.svg##{icon}"
    end
    refute_includes body, '&#x1F50D;', 'magnifier emoji must be gone'
    refute_includes body, '&#x2764;',  'heart emoji must be gone'
    assert_includes body, 'class="jumbotron"'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — emoji entities are still present and there is no `.jumbotron`.

- [ ] **Step 3: Rebuild each card**

In `views/about.erb`, replace each of the six card blocks. Peak Browser becomes:

```erb
  <div class="col-md-4">
    <a href="/peak_browser" class="jumbotron-link">
      <div class="jumbotron">
        <div class="col-icon">
          <%== erb :_icon, locals: { name: 'glasses', size: 'lg' } %>
        </div>
        <div class="col-labels">
          <h3>Peak Browser</h3>
          <div class="labels">
            <span class="label label-primary">ChIP</span>
            <span class="label label-primary">ATAC</span>
            <span class="label label-primary">Bisulfite</span>
          </div>
        </div>
      </div>
    </a>
  </div>
```

Repeat for the other five, using: `hand-holding-heart` / Enrichment Analysis / ChIP·ATAC·Bisulfite; `balance-scale-left` / Diff Analysis / ChIP·ATAC·Bisulfite; `bullseye` / Target Genes / ChIP; `compress-arrows-alt` / Colocalization / ChIP; `search` / Dataset Search / ChIP·ATAC·Bisulfite.

Wrap the two rows in `<div class="row align-height">` instead of `<div class="row g-3 mb-3">`.

- [ ] **Step 4: Add the jumbotron styles**

Append to `public/css/style.css`:

```css
/* ===== Homepage feature tiles (Bootstrap 3 .jumbotron, dropped in BS5) ===== */
.align-height {
  display: flex;
  flex-wrap: wrap;
}

.jumbotron-link {
  color: #333 !important;
  text-decoration: none !important;
  display: block;
  height: 100%;
}

.jumbotron {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 100%;
  padding: 30px 30px 30px 40px;
  margin-bottom: 30px;
  color: inherit;
  background-color: var(--ca-jumbotron-bg);
  border-radius: 6px;
}

.jumbotron .col-icon { padding-right: 5px; }
.jumbotron .col-labels { padding-left: 10px; text-align: left; }
.jumbotron h3 { margin: 0 0 10px; font-size: 24px; }

.labels span {
  display: inline-block;
  text-align: center;
  margin-left: 3px;
  padding: 0.4em;
}

/* Bootstrap 3 .label, dropped in BS5 */
.label {
  display: inline;
  padding: .2em .6em .3em;
  font-size: 75%;
  font-weight: 700;
  line-height: 1;
  color: #fff;
  text-align: center;
  white-space: nowrap;
  vertical-align: baseline;
  border-radius: .25em;
}

.label-primary { background-color: var(--ca-primary); }

@media (max-width: 767px) {
  .jumbotron { flex-direction: column; text-align: center; }
  .jumbotron .col-labels { text-align: center; }
}
```

Delete the now-dead `.feature-card` and `.feature-icon` rules from `style.css`.

- [ ] **Step 5: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 6: Visual check**

Screenshot http://localhost:9292/ and compare the card row against `docs/ui-parity-audit-2026-09-14.md`. Tiles should be grey, borderless, with a 70px black glyph on the left.

- [ ] **Step 7: Commit**

```bash
git add views/about.erb public/css/style.css test/routes/pages_test.rb
git commit -m "Rebuild homepage tiles as Bootstrap 3 style jumbotrons with real glyphs"
```

---

### Task 7: Genome tab species labels

**Files:**
- Modify: `frontend/components/genome-tabs.ts:53-58`

**Interfaces:**
- Consumes: `/api/genomes` → `Record<string, string>` mapping code to label (e.g. `{"hg38": "H. sapiens (hg38)"}`).

- [ ] **Step 1: Read the current render block**

Run: `sed -n '40,70p' frontend/components/genome-tabs.ts`
The button text is set with `button.textContent = code`.

- [ ] **Step 2: Accept and use labels**

Change the component so the tab list is built from label-bearing entries. Where the code currently does:

```ts
      button.textContent = code
```

make it:

```ts
      button.textContent = labels?.[code] ?? code
```

and thread a `labels?: Record<string, string>` option through the component's options object and its `render` signature. Keep the fallback — a missing label must still render the bare code rather than `undefined`.

- [ ] **Step 3: Pass labels from each page**

In `frontend/pages/peak-browser.ts`, `enrichment-analysis.ts`, `diff-analysis.ts`, `target-genes.ts` and `colo.ts`, the genome list already comes from the page-data JSON island or `/api/genomes`. Pass it as `labels` when constructing `GenomeTabs`.

- [ ] **Step 4: Type-check and build**

Run: `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: exit 0, 12 bundles written.

- [ ] **Step 5: Verify in the browser**

Reload http://localhost:9292/peak_browser — tabs should read `H. sapiens (hg38)`, `M. musculus (mm10)`, and so on.

- [ ] **Step 6: Commit**

```bash
git add frontend/components/genome-tabs.ts frontend/pages/*.ts
git commit -m "Show full species labels on genome tabs"
```

---

### Task 8: Button styling and labels

**Files:**
- Modify: `views/peak_browser.erb`, `target_genes.erb`, `colo.erb`
- Modify: `public/css/style.css`
- Test: `test/routes/pages_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  def test_action_buttons_are_solid_and_full_width
    get '/peak_browser'
    body = last_response.body
    assert_includes body, 'Download BED file'
    refute_includes body, 'btn-outline-primary'
    assert_includes body, 'btn-block'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — the page says "Download BED" and uses `btn-outline-primary`.

- [ ] **Step 3: Restore the Bootstrap 3 button block**

Append to `public/css/style.css`:

```css
/* ===== Bootstrap 3 .btn-block, dropped in BS5 ===== */
.btn-block {
  display: block;
  width: 100%;
}

.button-submit { margin-top: 5em; }
.button-submit .btn + .btn { margin-top: 5px; }
.button-submit .igv-help { display: block; text-align: right; font-size: 13px; margin: 4px 0; }
```

- [ ] **Step 4: Update the Peak Browser actions**

In `views/peak_browser.erb`, replace the `<div class="d-grid gap-2">` block with:

```erb
    <div class="button-submit">
      <button type="button" id="view-igv" class="btn btn-primary btn-lg btn-block">View on IGV</button>
      <a class="igv-help" href="https://github.com/inutano/chip-atlas/wiki#igv_doc"
         target="_blank" rel="noopener noreferrer">Error connecting to IGV?</a>
      <button type="button" id="download-bed" class="btn btn-primary btn-lg btn-block">Download BED file</button>
    </div>
```

- [ ] **Step 5: Update Target Genes and Colo**

In `views/target_genes.erb` and `views/colo.erb`, change every `btn-outline-primary` to `btn-primary` and add `btn-block`. Change the Target Genes distance radio labels from `±1 kb` / `±5 kb` / `±10 kb` to `±1k` / `±5k` / `±10k`.

- [ ] **Step 6: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add views/peak_browser.erb views/target_genes.erb views/colo.erb public/css/style.css test/routes/pages_test.rb
git commit -m "Restore solid full-width action buttons and production labels"
```

---

### Task 9: Experiment page section icons

**Files:**
- Modify: `views/experiment.erb`
- Test: `test/routes/pages_test.rb`

**Interfaces:**
- Consumes: the icon partial from Task 3.

- [ ] **Step 1: Write the failing test**

```ruby
  VIEW_ICONS = %w[file-alt tag microscope user-edit flask server cogs dna].freeze

  def test_experiment_page_headings_carry_icons
    get '/view?id=SRX019491'
    assert_equal 200, last_response.status
    VIEW_ICONS.each do |icon|
      assert_includes last_response.body, "chip-atlas.svg##{icon}",
                      "experiment page is missing the #{icon} icon"
    end
  end
```

Note: this test needs a seeded experiment. Add `SRX019491` to the fixtures in `test/test_helper.rb` if `seed_experiments` does not already provide it, matching the existing seed row shape.

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — no sprite references on the page.

- [ ] **Step 3: Add the glyphs**

In `views/experiment.erb`, prefix each heading with the partial:

| Heading | Icon |
|---|---|
| page title (`h1`, the SRX id) | `file-alt` |
| Sample Information Curated by ChIP-Atlas | `flask` |
| Antigen Information | `tag` |
| Cell Type Information | `microscope` |
| Original Experimental Metadata | `user-edit` |
| Sample Attributes | `flask` |
| Sequenced DNA Library | `file-alt` |
| Sequencing Platform | `server` |
| Read Processing Pipeline | `cogs` |
| per-genome sub-heading (e.g. `hg38`) | `dna` |
| "Pipeline docs" link | `external-link-alt` |

Example:

```erb
    <div class="card-header">
      <h5 class="mb-0">
        <%== erb :_icon, locals: { name: 'flask' } %>
        Sample Information Curated by ChIP-Atlas
      </h5>
    </div>
```

Restore the dropdown-button glyphs too: `eye` on Visualize, `chart-line` on Analyze, `download` on Download, `external-link-alt` on Link Out.

- [ ] **Step 4: Restore sub-heading weight**

Change the "Antigen Information", "Cell Type Information", "Sample Attributes", "Sequenced DNA Library" and "Sequencing Platform" headings from plain text to `<h4>`, and append to `public/css/style.css`:

```css
/* ===== Experiment detail sub-headings ===== */
.card-body h4 {
  font-size: 18px;
  font-weight: 500;
  margin: 0 0 12px;
}
```

- [ ] **Step 5: Run tests**

Run: `run-tests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add views/experiment.erb public/css/style.css test/routes/pages_test.rb test/test_helper.rb
git commit -m "Add section icons and restore heading hierarchy on the experiment page"
```

---

**Tier 1 checkpoint.** Re-screenshot all seven pages against production before starting Tier 2. Everything below changes behaviour, not just appearance.

---

# TIER 2 — CONTROLS

Restores the working surface: list boxes, typeaheads, numbered panel grids.

---

### Task 10: ListBox component

**Files:**
- Create: `frontend/components/list-box.ts`
- Modify: `public/css/style.css`

**Interfaces:**
- Produces:

```ts
export interface ListBoxOption { id: string; label: string; count?: number | null }

export interface ListBoxOptions {
  container: HTMLElement
  id: string
  size?: number                       // default 8
  options: ListBoxOption[]
  selected?: string
  onChange?: (id: string) => void
}

export class ListBox {
  constructor(opts: ListBoxOptions)
  setOptions(options: ListBoxOption[], selected?: string): void
  get value(): string | null
  set value(id: string | null)
}
```

Tasks 11–15 consume exactly these names.

- [ ] **Step 1: Write the component**

```ts
// frontend/components/list-box.ts
// Bootstrap 3 style multi-row list box: a <select size="8"> with counts.
// Replaces the old Flexselect control.

export interface ListBoxOption {
  id: string
  label: string
  count?: number | null
}

export interface ListBoxOptions {
  container: HTMLElement
  id: string
  size?: number
  options: ListBoxOption[]
  selected?: string
  onChange?: (id: string) => void
}

export class ListBox {
  private select: HTMLSelectElement
  private onChange?: (id: string) => void

  constructor(opts: ListBoxOptions) {
    this.onChange = opts.onChange

    const select = document.createElement('select')
    select.className = 'form-control list-box'
    select.id = opts.id
    select.size = opts.size ?? 8
    select.addEventListener('change', () => {
      if (this.onChange && select.value) this.onChange(select.value)
    })

    opts.container.innerHTML = ''
    opts.container.appendChild(select)
    this.select = select

    this.setOptions(opts.options, opts.selected)
  }

  setOptions(options: ListBoxOption[], selected?: string): void {
    this.select.innerHTML = ''
    for (const opt of options) {
      const el = document.createElement('option')
      el.value = opt.id
      el.textContent =
        opt.count === null || opt.count === undefined
          ? opt.label
          : `${opt.label} (${opt.count.toLocaleString()})`
      if (opt.id === selected) el.selected = true
      this.select.appendChild(el)
    }
  }

  get value(): string | null {
    return this.select.value || null
  }

  set value(id: string | null) {
    this.select.value = id ?? ''
  }
}
```

- [ ] **Step 2: Style it**

Append to `public/css/style.css`:

```css
/* ===== List box (Bootstrap 3 select[size]) ===== */
select.list-box {
  height: auto;
  padding: 0;
  overflow-y: auto;
  border: 1px solid #ccc;
  border-radius: 4px;
  background-image: none;
}

select.list-box option {
  padding: 2px 6px;
  line-height: 1.42857143;
}
```

- [ ] **Step 3: Type-check and build**

Run: `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add frontend/components/list-box.ts public/css/style.css
git commit -m "Add ListBox component for Bootstrap 3 style multi-row selects"
```

---

### Task 11: FacetFilter list-box mode

**Files:**
- Modify: `frontend/components/facet-filter.ts`

**Interfaces:**
- Consumes: `ListBox`, `ListBoxOption` from Task 10.
- Produces: `FacetFilter` accepts `render: 'listbox' | 'dropdown'` (default `'dropdown'` so nothing else breaks) and `mount: Record<string, HTMLElement>` mapping each facet key to the container it renders into, so the Peak Browser can scatter facets across separate panels.

- [ ] **Step 1: Read the current implementation**

Run: `cat frontend/components/facet-filter.ts`
Note how it builds each `<select>` and how the cascade refresh works. The bidirectional count update must be preserved exactly — it is a deliberate improvement over the old UI.

- [ ] **Step 2: Add the options**

Extend the options interface with `render` and `mount`, defaulting `render` to `'dropdown'`. When `render === 'listbox'`, construct a `ListBox` per facet into `mount[key]` instead of appending a labelled `<select>` to the single container.

- [ ] **Step 3: Route count updates through both renderers**

Wherever the component currently repopulates a `<select>`'s options after a cascade change, call `listBox.setOptions(options, selected)` in list-box mode. Counts are already computed; pass them through as `ListBoxOption.count`.

- [ ] **Step 4: Type-check and build**

Run: `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: exit 0. Existing pages still use dropdown mode and must be unchanged.

- [ ] **Step 5: Verify no regression**

Reload http://localhost:9292/peak_browser — it still renders dropdowns and the cascade still works.

- [ ] **Step 6: Commit**

```bash
git add frontend/components/facet-filter.ts
git commit -m "Add list-box rendering mode and per-facet mount points to FacetFilter"
```

---

### Task 12: Autocomplete paired list box

**Files:**
- Modify: `frontend/components/autocomplete.ts`
- Modify: `public/css/style.css`

**Interfaces:**
- Consumes: `ListBox` from Task 10.
- Produces: `Autocomplete` accepts `pairedList?: HTMLElement`. When supplied, a `ListBox` renders below the input, always showing the current filtered set; typing narrows it, selecting a row fires the same `onSelect` as the menu.

- [ ] **Step 1: Add the option**

Thread `pairedList?: HTMLElement` through the options interface. Build a `ListBox` into it at construction with the full option set.

- [ ] **Step 2: Filter on input**

On each input event, in addition to the existing dropdown menu behaviour, call `listBox.setOptions(filtered)`. Keep the existing substring matching — it is an intentional improvement over the old prefix-only Typeahead.

- [ ] **Step 3: Preserve accessibility**

The existing `aria-activedescendant` wiring on the dropdown menu must keep working. The paired list box is a real `<select>`, so it is keyboard-accessible on its own; do not add `aria-activedescendant` to it.

- [ ] **Step 4: Type-check and build**

Run: `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add frontend/components/autocomplete.ts public/css/style.css
git commit -m "Add paired list box to Autocomplete, replacing Flexselect behaviour"
```

---

### Task 13: Peak Browser panel grid

**Files:**
- Modify: `views/peak_browser.erb`
- Modify: `frontend/pages/peak-browser.ts`
- Modify: `public/css/style.css`
- Test: `test/routes/pages_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  def test_peak_browser_has_five_numbered_panels
    get '/peak_browser'
    body = last_response.body
    assert_includes body, '1. Track type class'
    assert_includes body, '2. Cell type Class'
    assert_includes body, '3. Threshold for Significance'
    assert_includes body, 'Track type (optional)'
    assert_includes body, 'Cell type (optional)'
    assert_includes body, 'class="panel panel-default"'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — the page has one card titled "Filter".

- [ ] **Step 3: Add the Bootstrap 3 panel CSS**

Append to `public/css/style.css`:

```css
/* ===== Bootstrap 3 .panel, dropped in BS5 ===== */
.panel {
  margin-bottom: 20px;
  background-color: #fff;
  border: 1px solid transparent;
  border-radius: 4px;
  box-shadow: 0 1px 1px rgba(0, 0, 0, .05);
}

.panel-default { border-color: var(--ca-panel-border); }

.panel-heading {
  padding: 10px 15px;
  border-bottom: 1px solid transparent;
  border-top-left-radius: 3px;
  border-top-right-radius: 3px;
}

.panel-default > .panel-heading {
  color: #333;
  background-color: var(--ca-panel-head);
  border-color: var(--ca-panel-border);
  border-bottom: 1px solid var(--ca-panel-border);
}

.panel-title { margin: 0; font-size: 16px; }
.panel-body { padding: 15px; }
```

- [ ] **Step 4: Rewrite the template**

This replaces the action-button block added in Task 8 as well — the markup below already contains the final version of it, so expect that part of the Task 8 diff to be superseded here. Task 8 still stands on its own if Tier 1 ships alone.

Replace the `<div class="row">` block below `#genome-tabs` in `views/peak_browser.erb` with:

```erb
<div class="row">
  <div class="col-md-4">
    <div class="panel panel-default">
      <div class="panel-heading"><h4 class="panel-title">1. Track type class</h4></div>
      <div class="panel-body"><div id="facet-track-class"></div></div>
    </div>
    <div class="panel panel-default">
      <div class="panel-heading"><h4 class="panel-title">Track type (optional)</h4></div>
      <div class="panel-body">
        <input class="form-control" id="track-subclass-input" type="text" placeholder="type to search">
        <div id="facet-track-subclass" class="mt-2"></div>
      </div>
    </div>
  </div>

  <div class="col-md-4">
    <div class="panel panel-default">
      <div class="panel-heading"><h4 class="panel-title">2. Cell type Class</h4></div>
      <div class="panel-body"><div id="facet-cell-type-class"></div></div>
    </div>
    <div class="panel panel-default">
      <div class="panel-heading"><h4 class="panel-title">Cell type (optional)</h4></div>
      <div class="panel-body">
        <input class="form-control" id="cell-type-subclass-input" type="text" placeholder="type to search">
        <div id="facet-cell-type-subclass" class="mt-2"></div>
      </div>
    </div>
  </div>

  <div class="col-md-4">
    <div class="panel panel-default">
      <div class="panel-heading">
        <h4 class="panel-title">
          3. Threshold for Significance
          <a class="info-btn" href="#" data-info="threshold" role="button" aria-label="About the significance threshold">&#x24D8;</a>
        </h4>
      </div>
      <div class="panel-body"><div id="facet-qval"></div></div>
    </div>

    <div class="button-submit">
      <button type="button" id="view-igv" class="btn btn-primary btn-lg btn-block">View on IGV</button>
      <a class="igv-help" href="https://github.com/inutano/chip-atlas/wiki#igv_doc"
         target="_blank" rel="noopener noreferrer">Error connecting to IGV?</a>
      <button type="button" id="download-bed" class="btn btn-primary btn-lg btn-block">Download BED file</button>
    </div>
    <div id="action-status" class="text-muted small mt-2" aria-live="polite"></div>
  </div>
</div>
```

- [ ] **Step 5: Wire the page script**

In `frontend/pages/peak-browser.ts`, construct `FacetFilter` with `render: 'listbox'` and the mount map:

```ts
  mount: {
    track_class:        document.getElementById('facet-track-class')!,
    track_subclass:     document.getElementById('facet-track-subclass')!,
    cell_type_class:    document.getElementById('facet-cell-type-class')!,
    cell_type_subclass: document.getElementById('facet-cell-type-subclass')!,
    qval:               document.getElementById('facet-qval')!,
  },
```

Attach an `Autocomplete` to `#track-subclass-input` with `pairedList` set to the `#facet-track-subclass` list box, and the same for cell type. Give the qval list box `size: 5` to match production.

- [ ] **Step 6: Run tests and build**

Run: `run-tests` then `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: both pass.

- [ ] **Step 7: Visual check**

Screenshot http://localhost:9292/peak_browser at 1440px and compare with the audit doc. Three columns, five panels, eight visible options per list box.

- [ ] **Step 8: Commit**

```bash
git add views/peak_browser.erb frontend/pages/peak-browser.ts public/css/style.css test/routes/pages_test.rb
git commit -m "Rebuild Peak Browser as a three-column numbered panel grid with list boxes"
```

---

### Task 14: Enrichment Analysis six-panel grid

**Files:**
- Modify: `views/enrichment_analysis.erb`
- Modify: `frontend/pages/enrichment-analysis.ts`
- Test: `test/routes/pages_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  EA_PANELS = [
    '1. Experiment type', '2. Cell type Class', '3. Threshold for Significance',
    '4. Enter dataset A', '5. Enter dataset B', '6. Analysis description'
  ].freeze

  def test_enrichment_analysis_has_six_numbered_panels
    get '/enrichment_analysis'
    EA_PANELS.each { |h| assert_includes last_response.body, h }
  end

  def test_enrichment_analysis_seeds_title_placeholders
    get '/enrichment_analysis'
    body = last_response.body
    assert_includes body, 'value="My project"'
    assert_includes body, 'value="Dataset A"'
    assert_includes body, 'value="Dataset B"'
    assert_includes body, 'Try with example'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — the page has four panels named `1. Filter` … `4. Analysis description`.

- [ ] **Step 3: Split the Filter card into three panels**

Restructure the template to a `row` of three `col-md-4` panels (Experiment type, Cell type Class, Threshold), then a second `row` of three `col-md-4` panels (dataset A, dataset B, Analysis description), using the `.panel.panel-default` markup from Task 13. Mount the facets into `#facet-track-class`, `#facet-cell-type-class`, `#facet-qval` as list boxes.

Production's panel 1 is titled **"1. Experiment type"**, not "Track type class" — match it exactly.

- [ ] **Step 4: Restore the missing affordances**

Add to panel 4:

```erb
        <div class="mt-2">
          <label class="text-muted small mb-0" for="dataset-a-file">Choose local file</label>
          <a class="linkExample float-end" href="#" id="try-example">Try with example</a>
        </div>
```

Add to panel 6, below the submit button:

```erb
        <p class="estimated-run-time mb-1">
          Estimated run time: <span id="estimated-run-time">&mdash;</span>
        </p>
        <p class="job-info mb-0">
          <a href="https://sc.ddbj.nig.ac.jp/en/guides/software/GridEngine/" target="_blank" rel="noopener noreferrer">node status (epyc.q)</a>
        </p>
```

Seed the three title inputs with `value="My project"`, `value="Dataset A"`, `value="Dataset B"`.

Keep the two disabled "gene-list mode only" radios — they are a genuine improvement over production.

- [ ] **Step 5: Wire the estimate and example**

In `frontend/pages/enrichment-analysis.ts`, call `POST /jobs/estimated_time` when the filter changes and write the result into `#estimated-run-time`. Wire `#try-example` to fetch `/examples/<genome>/bedA.txt` and drop it into the textarea.

- [ ] **Step 6: Run tests and build**

Run: `run-tests` then `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add views/enrichment_analysis.erb frontend/pages/enrichment-analysis.ts test/routes/pages_test.rb
git commit -m "Restore Enrichment Analysis six-panel layout and missing affordances"
```

---

### Task 15: Diff Analysis, Target Genes and Colo panels

**Files:**
- Modify: `views/diff_analysis.erb`, `views/target_genes.erb`, `views/colo.erb`
- Modify: `frontend/pages/diff-analysis.ts`, `target-genes.ts`, `colo.ts`
- Test: `test/routes/pages_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  def test_target_genes_has_an_antigen_list_box
    get '/target_genes'
    body = last_response.body
    assert_includes body, '1. Choose Antigen'
    assert_includes body, '2. Choose Distance from TSS'
    assert_includes body, 'id="antigen-list"'
    assert_includes body, 'class="panel panel-default"'
  end

  def test_diff_analysis_uses_panels
    get '/diff_analysis'
    assert_includes last_response.body, 'class="panel panel-default"'
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — both pages use `.card` and Target Genes has no list container.

- [ ] **Step 3: Rebuild Target Genes**

Change the two columns from `col-md-6` to `col-md-3` so the panels are content-sized like production, convert both to `.panel.panel-default`, and add the list container below the search input:

```erb
      <div class="panel-body">
        <input class="form-control" id="antigen-input" type="text" placeholder="type to search">
        <div id="antigen-list" class="mt-2"></div>
      </div>
```

In `frontend/pages/target-genes.ts`, give the `Autocomplete` on `#antigen-input` a `pairedList` of `#antigen-list`.

- [ ] **Step 4: Convert Diff Analysis and Colo**

Replace every `.card` / `.card-header` / `.card-body` in `views/diff_analysis.erb` and `views/colo.erb` with `.panel.panel-default` / `.panel-heading` + `h4.panel-title` / `.panel-body`. Keep the existing panel numbering and titles.

- [ ] **Step 5: Run tests and build**

Run: `run-tests` then `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add views/diff_analysis.erb views/target_genes.erb views/colo.erb frontend/pages/*.ts test/routes/pages_test.rb
git commit -m "Convert Diff Analysis, Target Genes and Colo to panel layout with list boxes"
```

---

### Task 16: Info buttons and Tutorial dropdowns

**Files:**
- Create: `views/_tutorial.erb`
- Modify: `views/peak_browser.erb`, `enrichment_analysis.erb`, `diff_analysis.erb`, `target_genes.erb`, `colo.erb`, `search.erb`
- Modify: `public/css/style.css`
- Test: `test/routes/pages_test.rb`

**Interfaces:**
- Produces: `erb :_tutorial, locals: { pdf: '<url>', movie: '<url>', togotv: '<url or nil>' }`.

- [ ] **Step 1: Write the failing test**

```ruby
  def test_analysis_pages_have_a_tutorial_dropdown
    %w[/peak_browser /enrichment_analysis /diff_analysis /target_genes /colo].each do |path|
      get path
      assert_includes last_response.body, 'Tutorial', "#{path} has no Tutorial button"
      assert_includes last_response.body, 'chip-atlas.svg#question-circle'
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — no Tutorial control on any page.

- [ ] **Step 3: Write the partial**

`views/_tutorial.erb`:

```erb
<div class="dropdown-help float-end">
  <div class="dropdown">
    <button class="btn btn-primary dropdown-toggle" type="button"
            id="tutorial-dropdown" data-bs-toggle="dropdown" aria-expanded="false">
      <%== erb :_icon, locals: { name: 'question-circle' } %>
      Tutorial
    </button>
    <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="tutorial-dropdown">
      <li><a class="dropdown-item" href="<%= pdf %>" target="_blank" rel="noopener noreferrer">PDF</a></li>
      <li><a class="dropdown-item" href="<%= movie %>" target="_blank" rel="noopener noreferrer">Movie</a></li>
      <% if defined?(togotv) && togotv %>
        <li><a class="dropdown-item" href="<%= togotv %>" target="_blank" rel="noopener noreferrer">Movie (統合TV, Japanese)</a></li>
      <% end %>
    </ul>
  </div>
</div>
```

Append to `public/css/style.css`:

```css
.dropdown-help { margin-top: 2em; }
.dropdown-menu { min-width: 250px; }

.info-btn {
  color: var(--ca-primary);
  text-decoration: none;
  margin-left: 4px;
  cursor: pointer;
}
```

- [ ] **Step 4: Add it to each page**

Immediately after the page header on each analysis page:

```erb
<%== erb :_tutorial, locals: {
  pdf: 'https://chip-atlas.dbcls.jp/data/manual/Peak_Browser/Peak_Browser.pdf',
  movie: 'https://youtu.be/qKNOkK-8hDo',
  togotv: 'http://doi.org/10.7875/togotv.2018.023'
} %>
```

Take the exact URLs per page from production — fetch each page and read its dropdown:

```bash
for p in peak_browser enrichment_analysis diff_analysis target_genes colo search; do
  echo "== $p"
  curl -s "https://chip-atlas.org/$p" | grep -A6 'dropdown-menu' | grep -oE 'href="[^"]+"'
done
```

- [ ] **Step 5: Add the ⓘ buttons**

Add `<a class="info-btn" data-info="KEY">&#x24D8;</a>` next to each heading and input that carries one in production. The seven Enrichment Analysis keys are: threshold, genomic-regions, gene-list, gene-count-table, permutation, dataset-b-bed, analysis-title. Wire them to Bootstrap popovers in the page script, with the copy taken from production's `infoBtn` handlers in `js/pj/pj.js`.

- [ ] **Step 6: Run tests and build**

Run: `run-tests` then `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add views/_tutorial.erb views/*.erb public/css/style.css frontend/pages/*.ts test/routes/pages_test.rb
git commit -m "Add Tutorial dropdowns and info buttons to analysis pages"
```

---

# TIER 3 — RESTORED FEATURES

---

### Task 17: Dataset Search default listing

Decision taken during planning: restore the default listing only. **No DataTables, no column sorting, no Copy/TSV export, no Simple/Detailed tabs.**

**Files:**
- Modify: `frontend/pages/search.ts`
- Modify: `views/search.erb`
- Modify: `lib/models/experiment_search.rb`
- Modify: `routes/api.rb:94-102`
- Test: `test/models/experiment_search_test.rb`, `test/routes/api_test.rb`

**Interfaces:**
- Produces: `GET /api/search` with an empty or absent `q` returns a page of all experiments ordered by `experiment_id`, in the same response shape as a query search: `{ total, returned, experiments }`.

- [ ] **Step 1: Write the failing test**

Add to `test/models/experiment_search_test.rb`:

```ruby
  def test_blank_query_lists_all_experiments
    result = ChipAtlas::ExperimentSearch.search('', limit: 2, offset: 0)
    assert_operator result[:total], :>, 0, 'blank query must list everything'
    assert_equal 2, result[:experiments].size
  end

  def test_blank_query_respects_genome_filter
    result = ChipAtlas::ExperimentSearch.search('', genome: 'hg38', limit: 10)
    assert result[:experiments].all? { |e| e[:genome] == 'hg38' }
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL — `search` returns `{ total: 0, … }` for a blank query (`experiment_search.rb:19`).

- [ ] **Step 3: Implement the listing branch**

In `lib/models/experiment_search.rb`, replace the early return:

```ruby
      return { total: 0, returned: 0, experiments: [] } if query.nil? || query.strip.empty?
```

with a branch that lists instead of matching:

```ruby
      return list_all(genome: genome, limit: limit, offset: offset) if query.nil? || query.strip.empty?
```

and add the method:

```ruby
    def list_all(genome: nil, limit: 20, offset: 0)
      if genome && !genome.empty?
        sql = <<~SQL
          SELECT #{COLUMNS.join(', ')}, COUNT(*) OVER() AS total_count
          FROM experiments_fts
          WHERE genome = ?
          ORDER BY experiment_id
          LIMIT ? OFFSET ?
        SQL
        rows = DB[sql, genome, limit.to_i, offset.to_i].all
      else
        sql = <<~SQL
          SELECT #{COLUMNS.join(', ')}, COUNT(*) OVER() AS total_count
          FROM experiments_fts
          ORDER BY experiment_id
          LIMIT ? OFFSET ?
        SQL
        rows = DB[sql, limit.to_i, offset.to_i].all
      end

      total = rows.first&.[](:total_count) || 0
      experiments = rows.map { |row| row.except(:total_count) }

      { total: total, returned: experiments.size, experiments: experiments }
    end
```

Note the `rank` column is absent here — `ORDER BY rank` is only valid on an FTS `MATCH` query, so `list_all` must not select it.

- [ ] **Step 4: Allow a blank q on the route**

In `routes/api.rb`, remove the guard that rejects a missing `q` on `/api/search`, so a bare `GET /api/search?limit=10` lists. Add to `test/routes/api_test.rb`:

```ruby
  def test_search_without_query_lists_experiments
    get '/api/search?limit=2'
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_operator data['total'], :>, 0
  end
```

- [ ] **Step 5: Load the first page on init**

In `frontend/pages/search.ts`, call the same search routine on page load with an empty query, and render the result count as production does:

```ts
  const label = `Showing ${offset + 1} to ${offset + returned} of ${total.toLocaleString()} entries`
```

Put it in a `<div id="search-count" class="text-muted mb-2">` added to `views/search.erb` above the table.

- [ ] **Step 6: Run tests and build**

Run: `run-tests` then `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: both pass.

- [ ] **Step 7: Verify against the real database**

```bash
curl -s "http://localhost:9292/api/search?limit=2" | python3 -m json.tool | head -20
```
Expected: `total` around 432,318 and two experiment rows.

- [ ] **Step 8: Commit**

```bash
git add lib/models/experiment_search.rb routes/api.rb frontend/pages/search.ts views/search.erb test/
git commit -m "List all experiments by default on Dataset Search"
```

---

### Task 18: Experiment Comparative Profile

Asset URLs and their contract are verified in `docs/ui-parity-audit-2026-09-14.md`. The section renders hidden and reveals each image only if it exists, exactly as production does.

**Files:**
- Modify: `lib/services/location_service.rb`
- Modify: `routes/pages.rb:27-40`
- Modify: `views/experiment.erb`
- Modify: `frontend/pages/experiment.ts`
- Modify: `routes/api.rb` (caching on `/api/remote_url_status`)
- Test: `test/services/location_service_test.rb`, `test/routes/pages_test.rb`

**Interfaces:**
- Produces: `LocationService#distribution_png_url`, `#correlation_png_url`, `#correlation_tsv_url`, each returning a `String`.

- [ ] **Step 1: Write the failing test**

Add to `test/services/location_service_test.rb`:

```ruby
  def test_distribution_png_url
    svc = ChipAtlas::LocationService.new(
      'condition' => { 'genome' => 'hg38', 'experiment_id' => 'SRX019491' }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/distribution/png/SRX019491.dist.png',
                 svc.distribution_png_url
  end

  def test_correlation_png_url
    svc = ChipAtlas::LocationService.new(
      'condition' => { 'genome' => 'hg38', 'experiment_id' => 'SRX019491' }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/correlation/png/SRX019491.cor.png',
                 svc.correlation_png_url
  end

  def test_correlation_tsv_url_underscores_spaces
    svc = ChipAtlas::LocationService.new(
      'condition' => {
        'genome' => 'hg38',
        'track_subclass' => 'Input control',
        'cell_type_subclass' => 'Adipose stromal cell'
      }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/correlation/tsv/' \
                 'hg38__x__Input_control__x__Adipose_stromal_cell.tsv',
                 svc.correlation_tsv_url
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `run-tests`
Expected: FAIL with `NoMethodError: undefined method 'distribution_png_url'`.

- [ ] **Step 3: Add the URL builders**

In `lib/services/location_service.rb`, add as public methods:

```ruby
    def distribution_png_url
      "#{ARCHIVE_BASE}/#{@genome}/distribution/png/#{@condition[:experiment_id]}.dist.png"
    end

    def correlation_png_url
      "#{ARCHIVE_BASE}/#{@genome}/correlation/png/#{@condition[:experiment_id]}.cor.png"
    end

    def correlation_tsv_url
      track = @condition[:track_subclass].to_s.tr(' ', '_')
      cell  = @condition[:cell_type_subclass].to_s.tr(' ', '_')
      "#{ARCHIVE_BASE}/#{@genome}/correlation/tsv/#{@genome}__x__#{track}__x__#{cell}.tsv"
    end
```

- [ ] **Step 4: Run the service tests**

Run: `run-tests`
Expected: the three new tests PASS.

- [ ] **Step 5: Pass the URLs to the template**

In `routes/pages.rb`, inside the `/view` handler after `@records` is set, build one profile entry per record:

```ruby
          @profiles = @records.map do |rec|
            svc = ChipAtlas::LocationService.new('condition' => {
              'genome' => rec[:genome],
              'experiment_id' => @expid,
              'track_subclass' => rec[:track_subclass],
              'cell_type_subclass' => rec[:cell_type_subclass]
            })
            {
              genome: rec[:genome],
              distribution: svc.distribution_png_url,
              correlation: svc.correlation_png_url,
              tsv: svc.correlation_tsv_url
            }
          end
```

- [ ] **Step 6: Add the section**

Append to `views/experiment.erb`, before the closing content:

```erb
<% if @profiles && !@profiles.empty? %>
  <div class="panel panel-default" id="statistics-panel" hidden>
    <div class="panel-heading">
      <h4 class="panel-title">
        <%== erb :_icon, locals: { name: 'chart-bar' } %>
        Experiment Comparative Profile
      </h4>
    </div>
    <div class="panel-body">
      <% @profiles.each do |p| %>
        <div class="statistics-section"
             data-genome="<%= p[:genome] %>"
             data-distribution-url="<%= p[:distribution] %>"
             data-correlation-url="<%= p[:correlation] %>"
             data-correlation-tsv="<%= p[:tsv] %>" hidden>
          <div class="row">
            <div class="col-md-6">
              <h4>
                <%== erb :_icon, locals: { name: 'chart-line' } %>
                Read and Peak Distribution
              </h4>
              <div class="text-center">
                <img class="profile-img distribution-img" alt="Read and peak distribution for <%= @expid %>" hidden>
              </div>
            </div>
            <div class="col-md-6">
              <h4>
                <%== erb :_icon, locals: { name: 'project-diagram' } %>
                Correlation-Based Clustering
              </h4>
              <div class="text-center">
                <img class="profile-img correlation-img" alt="Correlation clustering for <%= @expid %>" hidden>
              </div>
              <div class="text-center mt-2">
                <a class="btn btn-sm btn-light download-tsv" href="#" hidden>Download correlation TSV</a>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

Append to `public/css/style.css`:

```css
.profile-img {
  max-width: 100%;
  height: auto;
  border: 1px solid #ddd;
  border-radius: 4px;
}
```

- [ ] **Step 7: Probe and reveal**

In `frontend/pages/experiment.ts`, for each `.statistics-section`, call `remoteUrlStatus(url)` from `frontend/api/client.ts` for the distribution and correlation URLs. On `"200"`, set the `img.src` and clear its `hidden`; reveal the section and the panel if either image resolved. Reveal the TSV link only if its probe returns `"200"`. Use `el.hidden = false`, never `style.display`.

This is the first production caller of `/api/remote_url_status`.

- [ ] **Step 8: Cache the probe endpoint**

Open issue #223 asks for this and the section makes it live traffic. In `routes/api.rb`, add to the `/api/remote_url_status` handler before the request:

```ruby
          cache_control :public, max_age: 3600
```

- [ ] **Step 9: Write the render test**

```ruby
  def test_experiment_page_has_a_comparative_profile_section
    get '/view?id=SRX019491'
    body = last_response.body
    assert_includes body, 'Experiment Comparative Profile'
    assert_includes body, 'distribution/png/SRX019491.dist.png'
    assert_includes body, 'correlation/png/SRX019491.cor.png'
    assert_includes body, 'id="statistics-panel"'
  end
```

- [ ] **Step 10: Run tests and build**

Run: `run-tests` then `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json && npm run build`
Expected: both pass.

- [ ] **Step 11: Verify in the browser**

Open http://localhost:9292/view?id=SRX019491. Both images should appear. Confirm the network panel shows two `/api/remote_url_status` calls returning `200`.

- [ ] **Step 12: Commit**

```bash
git add lib/services/location_service.rb routes/pages.rb routes/api.rb views/experiment.erb frontend/pages/experiment.ts public/css/style.css test/
git commit -m "Restore Experiment Comparative Profile section"
```

---

### Task 19: Final evaluation and regression gate

The last task. It proves the whole plan landed and leaves behind evidence a reviewer can check without re-running anything.

**Files:**
- Modify: `docs/ui-parity-audit-2026-09-14.md`
- Modify: `.github/workflows/ci.yml`
- Test: whole suite

- [ ] **Step 1: Run every automated check**

```bash
bash script/dev/test.sh
./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json
NODE_ENV=production npm run build
bash script/dev/ui-checklist.sh
```

Expected: 0 failures; tsc exit 0; 12 bundles; **SCORE at the full marker count**. Any FAIL line names a task that did not finish — go back and finish it rather than editing the marker list.

- [ ] **Step 2: Responsive check**

```bash
for w in 400 768 1024 1440; do
  chromium --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --window-size=$w,1400 --virtual-time-budget=9000 \
    --screenshot=tmp/ui-parity/width-$w.png http://localhost:9292/peak_browser >/dev/null 2>&1
done
```

Open each. Required at 400px: no horizontal scrolling, navbar collapses to the toggler, the three panel columns stack, list boxes stay inside the viewport.

- [ ] **Step 3: Keyboard and focus pass**

Tab through `/peak_browser` from the top. Every list box, both typeahead inputs, the Tutorial dropdown, both action buttons and every ⓘ button must be reachable in visual order with a visible focus ring. Fix any element that traps focus or shows none.

- [ ] **Step 4: Contact sheets for the record**

```bash
bash script/dev/ui-parity.sh
```

Review each sheet against `docs/ui-parity-audit-2026-09-14.md`. For any component still visibly different, either fix it or add a line to the audit's open-questions section saying why it stays different.

- [ ] **Step 5: Wire the checks into CI**

In `.github/workflows/ci.yml`, add a step after "Set up database" and before the boot step:

```yaml
      - name: Run test suite
        run: bundle exec ruby -Itest -e 'Dir.glob("./test/**/*_test.rb").sort.each { |f| require f }'

      - name: Build frontend
        run: |
          npm ci
          npx tsc --noEmit -p frontend/tsconfig.json
          NODE_ENV=production npm run build
```

This closes the long-standing gap where CI never ran the test suite and never built the frontend (open issue #206).

- [ ] **Step 6: Record the outcome in the audit doc**

Add a "Status" section at the top of `docs/ui-parity-audit-2026-09-14.md`:

```markdown
## Status (updated <DATE>)

Implemented by `docs/superpowers/plans/2026-09-14-ui-parity-with-production.md`.
Parity checklist score: **<N>/<N>**. Remaining intentional differences are
listed under "Out of scope / open questions".
```

Mark each component delta above with **RESOLVED** or **INTENTIONAL**.

- [ ] **Step 7: Commit**

```bash
git add docs/ui-parity-audit-2026-09-14.md .github/workflows/ci.yml
git commit -m "Record parity evaluation results and run tests plus frontend build in CI"
```

---

## Final verification

- [ ] `bash script/dev/test.sh` — 0 failures, 0 errors.
- [ ] `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json` — exit 0.
- [ ] `NODE_ENV=production npm run build` — 12 bundles.
- [ ] `bash script/dev/ui-checklist.sh` — full score.
- [ ] Contact sheets reviewed at 1440px; 400px checked for horizontal scroll.
- [ ] Keyboard pass on `/peak_browser` complete.

## Open questions to settle before Tier 3 ships

- Does **Demo** belong in the production navbar? It has no production counterpart and no icon.
- Confirm the pipeline still regenerates the Comparative Profile PNGs — the published files carry Sept 2025 timestamps.
- The **Simple / Detailed search** tabs are not being restored. Confirm that is acceptable, or open a follow-up.
