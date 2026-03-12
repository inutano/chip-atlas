## ChIP-Atlas for AI Agents

ChIP-Atlas is a comprehensive database of public ChIP-seq, ATAC-seq, DNase-seq, and Bisulfite-seq experiments. This page describes how AI agents can query ChIP-Atlas programmatically via the MCP (Model Context Protocol) server or the HTTP API directly.

**New here?** Check out the [hands-on demo tutorial](/demo) for step-by-step scenarios you can try with your preferred LLM.

---

## MCP Server

The ChIP-Atlas MCP server provides 10 read-only tools for exploring and retrieving epigenomic data. It uses stdio transport and is compatible with Claude Desktop, Claude Code, and other MCP clients.

**Installation:**

```
cd mcp && npm install && npm run build
```

**Configuration (Claude Desktop / Claude Code):**

```json
{
  "mcpServers": {
    "chipatlas": {
      "command": "node",
      "args": ["path/to/chip-atlas/mcp/dist/index.js"]
    }
  }
}
```

Set `CHIP_ATLAS_BASE_URL` to override the default base URL (`https://chip-atlas.org`).

Source code: [github.com/inutano/chip-atlas/tree/master/mcp](https://github.com/inutano/chip-atlas/tree/master/mcp)

**Machine-readable API spec:** [OpenAPI 3.1 (openapi.yaml)](/openapi.yaml)

---

## Data Model

ChIP-Atlas organizes data along these dimensions:

| Dimension | Examples | Notes |
|-----------|----------|-------|
| **Genome** | hg38, mm10, dm6, sacCer3 | Assembly identifier |
| **Experiment class** (agClass) | Histone, TFs and others, ATAC-Seq, DNase-seq, Bisulfite-Seq | Top-level category |
| **Antigen subclass** (agSubClass) | H3K4me3, CTCF, p300 | Specific target |
| **Cell type class** (clClass) | Blood, Brain, Liver, All cell types | Broad tissue/cell category |
| **Cell type subclass** (clSubClass) | K-562, HeLa, GM12878 | Specific cell line or tissue |
| **Q-value** | 1, 5, 10, 50, 100 | Peak-call significance threshold (smaller = stricter) |

Experiments are identified by SRX (SRA experiment) or GSM (GEO sample) accession IDs.

---

## Tools Reference

### Browsing the hierarchy

Start broad and drill down through the classification tree.

**`chipatlas_list_genomes`** — Returns available genome assemblies as a string array. No parameters. This is the typical entry point.

**`chipatlas_list_experiment_types`** — Lists experiment classes (e.g. Histone, TFs and others, ATAC-Seq). Call without arguments for the static list. Call with `genome` + `clClass` to get experiment counts for a specific context.

| Parameter | Required | Description |
|-----------|----------|-------------|
| genome | No | Genome assembly (e.g. hg38). Required with clClass. |
| clClass | No | Cell type class (e.g. "Blood"). Use "All cell types" for all. |

**`chipatlas_list_sample_types`** — Lists cell type classes with experiment counts.

| Parameter | Required | Description |
|-----------|----------|-------------|
| genome | Yes | Genome assembly |
| agClass | Yes | Experiment class (e.g. "Histone") |

**`chipatlas_list_antigens`** — Lists antigen subclasses (e.g. H3K4me3, CTCF) with counts.

| Parameter | Required | Description |
|-----------|----------|-------------|
| genome | Yes | Genome assembly |
| agClass | Yes | Experiment class |
| clClass | No | Cell type class to filter by |

**`chipatlas_list_cell_types`** — Lists cell type subclasses with counts.

| Parameter | Required | Description |
|-----------|----------|-------------|
| genome | Yes | Genome assembly |
| agClass | Yes | Experiment class |
| clClass | No | Cell type class to filter by |

### Searching and retrieving experiments

**`chipatlas_search_experiments`** — Full-text search across all experiment fields (accession IDs, genome, antigen, cell type, etc.).

| Parameter | Required | Description |
|-----------|----------|-------------|
| query | Yes | Search keyword (e.g. "H3K4me3", "HeLa", "SRX123456") |
| limit | No | Max results to return (default 20, max 100) |

Returns structured records with fields: `srx`, `sra`, `geo`, `genome`, `agClass`, `agSubClass`, `clClass`, `clSubClass`.

**`chipatlas_get_experiment`** — Detailed metadata for a single experiment.

| Parameter | Required | Description |
|-----------|----------|-------------|
| expid | Yes | Experiment ID (e.g. SRX123456 or GSM123456) |

### Analysis data

**`chipatlas_get_colocalization`** — Colocalization analysis index for a genome: which antigen/cell type combinations have precomputed results.

| Parameter | Required | Description |
|-----------|----------|-------------|
| genome | Yes | Genome assembly |

**`chipatlas_get_target_genes`** — Target gene analysis availability. Returns a mapping of genomes to lists of antigens with precomputed data. No parameters.

**`chipatlas_get_bed_url`** — Generates a download URL for assembled peak-call BED files.

| Parameter | Required | Description |
|-----------|----------|-------------|
| genome | Yes | Genome assembly |
| agClass | Yes | Experiment class |
| agSubClass | No | Antigen subclass (e.g. "H3K4me3") |
| clClass | No | Cell type class |
| clSubClass | No | Cell type subclass |
| qval | No | Q-value threshold (e.g. "5", "10") |

---

## HTTP API Endpoints

These are the underlying REST endpoints. The MCP tools wrap these, but agents can also call them directly.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/data/list_of_genome.json` | List genome assemblies |
| GET | `/data/list_of_experiment_types.json` | List experiment types (static) |
| GET | `/data/experiment_types?genome=X&clClass=Y` | Experiment types with counts |
| GET | `/data/sample_types?genome=X&agClass=Y` | Cell type classes with counts |
| GET | `/data/chip_antigen?genome=X&agClass=Y&clClass=Z` | Antigen subclasses with counts |
| GET | `/data/cell_type?genome=X&agClass=Y&clClass=Z` | Cell type subclasses with counts |
| GET | `/data/ExperimentList.json` | Full experiment list (large) |
| GET | `/data/exp_metadata.json?expid=X` | Single experiment metadata |
| GET | `/data/colo_analysis.json?genome=X` | Colocalization analysis index |
| GET | `/data/target_genes_analysis.json` | Target genes analysis index |
| POST | `/download` | Get BED file download URL |

The POST `/download` endpoint accepts a JSON body: `{"condition": {"genome": "...", "agClass": "...", ...}}`.

---

## Common Workflows

### Find what data is available for a genome

```
chipatlas_list_genomes()
chipatlas_list_experiment_types(genome="hg38", clClass="All cell types")
chipatlas_list_sample_types(genome="hg38", agClass="Histone")
```

### Search for specific experiments

```
chipatlas_search_experiments(query="CTCF K-562")
chipatlas_get_experiment(expid="SRX018625")
```

### Get a download URL for peak data

```
chipatlas_list_antigens(genome="hg38", agClass="Histone", clClass="Blood")
chipatlas_get_bed_url(genome="hg38", agClass="Histone", agSubClass="H3K4me3", clClass="Blood", qval="5")
```

### Check available analyses

```
chipatlas_get_target_genes()
chipatlas_get_colocalization(genome="hg38")
```

---

## Tips

- **Start with `chipatlas_list_genomes`** if the user hasn't specified a genome.
- **`agClass` values are fixed strings**: "Histone", "TFs and others", "RNA polymerase", "Input control", "ATAC-Seq", "DNase-seq", "Bisulfite-Seq". Use `chipatlas_list_experiment_types` to confirm.
- **`clClass` values are case-sensitive.** Use `chipatlas_list_sample_types` to discover valid values.
- **`search_experiments` downloads a large dataset** on first call. Prefer browsing tools when you know the classification.
- **Q-value**: lower = stricter peak calling. 5 or 10 are reasonable defaults.
- **BED file URLs** from `chipatlas_get_bed_url` are direct download links to potentially large files. Present them to the user rather than fetching them.
