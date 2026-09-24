# Owner feedback round 2 (2026-09-24) — specification

Source: the owner's message of 2026-09-24 after testing the sengu branch on the
test EC2 instance (http://13.112.186.37/, commit 05601bb) and comparing it with
production (https://chip-atlas.org, the `master` branch of this repository).
Each item is quoted verbatim, followed by the binding interpretation used by
the implementation plan `docs/superpowers/plans/2026-09-24-owner-feedback-round-2.md`.
"Original" always means production / `master`.

## R1 — Peak Browser: IGV genome must be given as a JSON URL

> TAIRの peak browser が動かない。genome = https://chip-atlas.dbcls.jp/data/genome/TAIR12/TAIR12.json を指定する。他のゲノムアセンブリも同様に .json を指定するように変更。

The IGV `load` command (and any other IGV genome reference the app emits) must
pass `genome=https://chip-atlas.dbcls.jp/data/genome/<assembly>/<assembly>.json`
for **every** assembly (hg38, mm10, rn6, dm6, ce11, sacCer3, TAIR12), not the
bare assembly id. Documentation that shows the IGV URL follows.

## R2 — Enrichment Analysis: gene-list submissions fail with 502

> Enrichment Analysis で 4. Gene list を選択すると動かない。コンソールでは 502 bad gateway が出ている。

Established: selecting the radio makes no request; the 502 is the app's own
`POST /jobs/submit` answer ("Compute backend rejected the submission") for
gene-list mode. The root cause (payload/field mismatch with WABI) must be
fixed so that a gene-list submission with the example data is accepted, and a
rejected submission must be logged with the backend's status and body.

## R3 — Enrichment Analysis: panel 5 must follow the dataset-A type, hiding not disabling

> Enrichment Analysis で Genomic regions / Gene list を切り替えたときに 5 のパネルの内容が変化していない。グレーアウトではなく非表示がオリジナルの挙動。

Panel 5's choices must change with the dataset-A radio exactly as the original
does: irrelevant choices are hidden (not shown disabled), and the default
choice after a switch is the original's.

## R4 — Enrichment Analysis: "Try with example" availability

> Enrichment Analysis で 5. BED を選択した場合に try with example が出てこない。4 Gene list -> 5. Gene list の場合も同様に try with example が出ない。オリジナルに合わせて出す。

"Try with example" must be offered wherever the original offers it, including
dataset B = Genomic regions (BED) and dataset A = Gene list → dataset B = Gene
list, and must fill the same field with the matching example.

## R5 — Enrichment Analysis: radio change clears the form

> 4. で try with example を押して example data を埋めた状態で Genomic regions などに切り替えてもフォームの value がクリアされない。オリジナルの挙動はラジオボタンを変更するとフォームをクリアする。

Changing a dataset-type radio clears the corresponding text input(s) exactly as
the original does.

## R6 — Info popovers dismiss on outside click

> info button をクリックすると吹き出しが出るが、どうすれば消えるかが自明ではない。吹き出しの範囲外をクリックすると消えるようにしたい。

Clicking anywhere outside an open info popover (and outside its trigger)
closes it. Existing ways to close (toggle, Escape if present) stay.

## R7 — Facet list items: match the original's type size and spacing

> facet track 内のアイテムのフォントサイズがやや大きく、マージンが少ない。オリジナルのデザインに合わせたい。

List-box rows in the facet panels get the original's font size, line height
and padding/margins (measured on production), on every page that uses them.

## R8 — Home page feature cards: top-align icon and label columns

> トップページの6つの機能の jumbotron 内部の col-icon と col-label が、隣り合う別の column 同士で中央揃えになっている。オリジナルと同様に上揃いにしたい。

Inside each of the six feature cards the icon column and the label column are
aligned to the top, as on production, instead of being vertically centred.

## R9 — Search results: show the hit in context, expand without duplication

> Search で検索した場合に、ヒットした箇所が attributes だった場合、 attributes が初期状態で折りたたまれているとユーザが気付かない。現在は、先頭から fix length で表示しているが、ヒットした部分の前後固定長テキストを表示するようにしたい。また、クリッカブルなテキストと、クリックすると表示されるテキストが重複しているので、click to expand として実装するべき。

When a result matches inside the attributes, the collapsed preview shows a
fixed-length window of the attributes around the (first) hit rather than the
first N characters. The preview is a single "click to expand" control: expanding
replaces the preview with the full attributes (no duplicated text), and the
full text can be collapsed again.

## R10 — Search: prefix matching

> Search で部分一致を実装したい。K562 ではヒットするが K56 ではヒットしないのが不便。

A query term matches tokens that start with it (`K56` finds `K562`), for every
term of a multi-word query, without breaking quoted phrases or the existing
sanitisation. No metadata reload may be required.

## R11 — Navbar: remove the ID form and Go button

> navbar の ID フォームと Go ボタンをなくすことにしました。そうすることで Search が目立ち、クリッカブルであることが自明になります。IDを直接 navbar に入力して view ページに飛ぶユースケースはあまり使われていないのではないかというのがチームの見解です。

The navbar's experiment-ID input and Go button are removed on every page,
together with their JavaScript, CSS, tests, checklist markers and documentation.
The "Search" navbar item remains and must read as clickable.

## R12 — Search by GSE / BioProject / BioSample: feasibility

> Search で GSE ID, BioProject, BioSample ID でも検索したいという要望があがりました。データベースロード時に含むことができるかどうか、確認してください。

This is an investigation item: determine whether these identifiers can be
added at metadata-load time (source files, cost, coverage) and report to the
owner with a recommendation. Implementation only if the owner decides so.

## Out of scope

Anything not listed above. Production behaviour is the reference for R3–R8;
the owner's wording is the reference for R9–R11.
