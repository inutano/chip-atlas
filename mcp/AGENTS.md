# ChIP-Atlas MCP Server — Agent Guide

This MCP server provides read-only access to [ChIP-Atlas](https://chip-atlas.org), a comprehensive database of public ChIP-seq, ATAC-seq, DNase-seq, and Bisulfite-seq experiments. Use these tools to help users explore epigenomic data, find experiments, and retrieve analysis results.

## Data Model

ChIP-Atlas organizes data along these dimensions:

| Dimension | Examples | Notes |
|-----------|----------|-------|
| **Genome** | `hg38`, `mm10`, `dm6`, `sacCer3` | Assembly identifier |
| **Experiment class** (`agClass`) | `Histone`, `TFs and others`, `ATAC-Seq`, `DNase-seq`, `Bisulfite-Seq` | Top-level experiment category |
| **Antigen subclass** (`agSubClass`) | `H3K4me3`, `CTCF`, `p300` | Specific target within the class |
| **Cell type class** (`clClass`) | `Blood`, `Brain`, `Liver`, `All cell types` | Broad tissue/cell category |
| **Cell type subclass** (`clSubClass`) | `K-562`, `HeLa`, `GM12878` | Specific cell line or tissue |
| **Q-value** | `1`, `5`, `10`, `50`, `100` | Peak-call significance threshold (smaller = stricter) |

Experiments are identified by SRX (SRA experiment) or GSM (GEO sample) accession IDs.

## Tools

### Browsing the hierarchy

These tools let you navigate the classification tree. Start broad and drill down.

**`chipatlas_list_genomes`** — Entry point. Returns available genome assemblies as a string array.

**`chipatlas_list_experiment_types`** — Lists experiment classes. Call without arguments for the static list; call with `genome` + `clClass` to get experiment counts for a specific context.

**`chipatlas_list_sample_types`** — Given a `genome` and `agClass`, returns cell type classes with counts. Use this to see which tissues/cell types have data for a given experiment type.

**`chipatlas_list_antigens`** — Given a `genome` and `agClass`, returns antigen subclasses with counts. Optionally filter by `clClass`.

**`chipatlas_list_cell_types`** — Given a `genome` and `agClass`, returns cell type subclasses with counts. Optionally filter by `clClass`.

### Searching and retrieving experiments

**`chipatlas_search_experiments`** — Full-text search across all experiment fields. Accepts any keyword (gene name, cell type, accession ID, genome, etc.). Returns structured records with `srx`, `genome`, `agClass`, `agSubClass`, `clClass`, `clSubClass` fields. Use `limit` to control result count (default 20, max 100).

**`chipatlas_get_experiment`** — Fetches detailed metadata for a single experiment by its SRX or GSM ID. Returns attributes like title, read info, and classification across all genome assemblies the experiment maps to.

### Analysis data

**`chipatlas_get_colocalization`** — Returns the colocalization analysis index for a genome: which antigens and cell types have precomputed colocalization results.

**`chipatlas_get_target_genes`** — Returns a genome-to-antigen mapping showing which combinations have precomputed target gene analysis data.

**`chipatlas_get_bed_url`** — Generates a download URL for assembled peak-call BED files. Requires `genome` and `agClass`; optionally narrow with `agSubClass`, `clClass`, `clSubClass`, and `qval`.

## Common Workflows

### 1. "What histone mark data is available for human blood cells?"

```
chipatlas_list_antigens(genome="hg38", agClass="Histone", clClass="Blood")
```

This returns antigens like H3K4me3, H3K27ac, etc. with experiment counts.

### 2. "Find experiments for CTCF in K-562 cells"

```
chipatlas_search_experiments(query="CTCF K-562")
```

Or for a more targeted approach, combine browsing tools:

```
chipatlas_list_antigens(genome="hg38", agClass="TFs and others", clClass="Blood")
  → confirms CTCF is available
chipatlas_search_experiments(query="CTCF K-562", limit=50)
  → returns matching experiments
```

### 3. "Get details for experiment SRX100267"

```
chipatlas_get_experiment(expid="SRX100267")
```

### 4. "What genomes and antigens have target gene analysis?"

```
chipatlas_get_target_genes()
```

Returns e.g. `{ "hg38": ["H3K4me3", "H3K27ac", ...], "mm10": [...] }`.

### 5. "Download H3K4me3 peaks for mouse embryonic stem cells"

```
chipatlas_list_genomes()
  → pick mm10
chipatlas_list_sample_types(genome="mm10", agClass="Histone")
  → find the relevant clClass (e.g. "Pluripotent stem cell")
chipatlas_list_cell_types(genome="mm10", agClass="Histone", clClass="Pluripotent stem cell")
  → find the specific clSubClass
chipatlas_get_bed_url(genome="mm10", agClass="Histone", agSubClass="H3K4me3", clClass="Pluripotent stem cell", clSubClass="ES-E14", qval="5")
```

### 6. "What colocalization data exists for the human genome?"

```
chipatlas_get_colocalization(genome="hg38")
```

Returns `antigen` and `cellline` mappings showing available analysis combinations.

## Tips for Agents

- **Start with `list_genomes`** if the user hasn't specified a genome. Don't guess assembly names.
- **Use `search_experiments` for free-text queries.** It searches across all fields — accession IDs, genome, antigen, cell type. It's the fastest way to find specific experiments.
- **Use the browsing tools to explore what's available** before constructing download requests. The hierarchy is: genome → experiment class → antigen/cell type → subclass.
- **`clClass` values are case-sensitive.** Use `list_sample_types` to discover the exact strings.
- **`agClass` values are specific strings**: `"Histone"`, `"TFs and others"`, `"RNA polymerase"`, `"Input control"`, `"ATAC-Seq"`, `"DNase-seq"`, `"Bisulfite-Seq"`. Use `list_experiment_types` to confirm.
- **The `search_experiments` tool downloads a large dataset on first call**, so prefer the browsing tools when you know the classification and just need counts or available options.
- **Q-value for `get_bed_url`**: lower values mean stricter peak calling. `"5"` or `"10"` are reasonable defaults if the user doesn't specify.
- **BED URLs returned by `get_bed_url`** are direct download links. Present them to the user rather than attempting to fetch the files (they can be very large).
