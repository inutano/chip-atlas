## Demo: Using ChIP-Atlas with AI Agents

This tutorial walks you through querying ChIP-Atlas using AI agents. You'll learn three integration methods — **llms.txt**, **MCP server**, and **HTTP API** — through hands-on scenarios with real data.

**What is ChIP-Atlas?** A comprehensive database of over 1 million public ChIP-seq, ATAC-seq, DNase-seq, and Bisulfite-seq experiments across 10+ genome assemblies. All data is uniformly processed and classified by genome, experiment type, antigen, and cell type.

---

## 1. Quick Start: llms.txt

The fastest way to get started — no setup required. Just paste a URL into any LLM chat.

**Step 1:** Copy this URL:

```
https://chip-atlas.org/llms.txt
```

**Step 2:** Paste it into your preferred LLM (ChatGPT, Claude, Gemini, etc.) along with a question:

> Here is the documentation for ChIP-Atlas: https://chip-atlas.org/llms.txt
>
> What histone modification data is available for human blood cells?

The LLM will read the llms.txt file, understand the API, and answer your question — often making API calls on your behalf.

**What's in llms.txt?** A machine-readable summary of ChIP-Atlas: features, API endpoints, data model, and links to full documentation. It follows the [llms.txt standard](https://llmstxt.org/) so any LLM can understand it.

---

## 2. Setup: MCP Server

The MCP (Model Context Protocol) server gives AI agents structured tool access to ChIP-Atlas. This is the most powerful integration method.

### Prerequisites

- Node.js 18+
- Git
- Claude Desktop or Claude Code (or any MCP-compatible client)

### Build the server

```bash
git clone https://github.com/inutano/chip-atlas.git
cd chip-atlas/mcp
npm install
npm run build
```

### Configure Claude Desktop

Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "chipatlas": {
      "command": "node",
      "args": ["/absolute/path/to/chip-atlas/mcp/dist/index.js"]
    }
  }
}
```

### Configure Claude Code

Add to your Claude Code settings (`.claude/settings.json` or `.mcp.json`):

```json
{
  "mcpServers": {
    "chipatlas": {
      "command": "node",
      "args": ["/absolute/path/to/chip-atlas/mcp/dist/index.js"]
    }
  }
}
```

### Verify

Restart your client and ask:

> What genomes are available in ChIP-Atlas?

The agent should call `chipatlas_list_genomes` and return a list of assemblies (hg38, mm10, dm6, etc.).

---

## 3. Scenario 1: Explore Available Data

**Question:** *"What histone modification data exists for human blood cells?"*

### With MCP tools

The agent will make these tool calls in sequence:

**Step 1** — List experiment types for human blood:

```
chipatlas_list_experiment_types(genome="hg38", clClass="Blood")
```

Expected: Returns experiment classes with counts, showing how many Histone, TF, ATAC-seq experiments exist for blood cells.

**Step 2** — List specific histone marks available:

```
chipatlas_list_antigens(genome="hg38", agClass="Histone", clClass="Blood")
```

Expected: Returns antigens like H3K4me3, H3K27ac, H3K27me3, etc. with experiment counts.

**Step 3** — List specific blood cell types:

```
chipatlas_list_cell_types(genome="hg38", agClass="Histone", clClass="Blood")
```

Expected: Returns cell lines/types like K-562, GM12878, CD4+ T cells, etc.

### With HTTP API (curl)

```bash
# Step 1: Experiment types for blood
curl "https://chip-atlas.org/data/experiment_types?genome=hg38&clClass=Blood"

# Step 2: Histone marks in blood
curl "https://chip-atlas.org/data/chip_antigen?genome=hg38&agClass=Histone&clClass=Blood"

# Step 3: Blood cell types
curl "https://chip-atlas.org/data/cell_type?genome=hg38&agClass=Histone&clClass=Blood"
```

---

## 4. Scenario 2: Find Specific Experiments

**Question:** *"Find CTCF ChIP-seq experiments in K-562 cells"*

### With MCP tools

**Step 1** — Search by keywords:

```
chipatlas_search_experiments(query="CTCF K-562")
```

Expected: Returns a list of experiments matching both CTCF and K-562, with fields like:

```json
{
  "srx": "SRX018625",
  "genome": "hg38",
  "agClass": "TFs and others",
  "agSubClass": "CTCF",
  "clClass": "Blood",
  "clSubClass": "K-562"
}
```

**Step 2** — Get detailed metadata for a specific experiment:

```
chipatlas_get_experiment(expid="SRX018625")
```

Expected: Full metadata including title, source URLs, read counts, and quality metrics.

### With HTTP API (curl)

```bash
# Search experiments (uses FTS)
curl "https://chip-atlas.org/data/search_experiments?query=CTCF+K-562&limit=5"

# Get experiment details
curl "https://chip-atlas.org/data/exp_metadata.json?expid=SRX018625"
```

---

## 5. Scenario 3: Download Peak-Call Data

**Question:** *"Get H3K4me3 peak data for mouse embryonic stem cells"*

### With MCP tools

**Step 1** — Confirm the antigen exists for mouse:

```
chipatlas_list_antigens(genome="mm10", agClass="Histone")
```

**Step 2** — Find the right cell type class:

```
chipatlas_list_sample_types(genome="mm10", agClass="Histone")
```

Look for a class containing embryonic stem cells (likely "Pluripotent stem cell" or similar).

**Step 3** — Get the download URL:

```
chipatlas_get_bed_url(
  genome="mm10",
  agClass="Histone",
  agSubClass="H3K4me3",
  clClass="Pluripotent stem cell",
  qval="5"
)
```

Expected: Returns a direct download URL for the assembled BED file.

### With HTTP API (curl)

```bash
# Check available cell type classes
curl "https://chip-atlas.org/data/sample_types?genome=mm10&agClass=Histone"

# Get download URL
curl -X POST "https://chip-atlas.org/download" \
  -H "Content-Type: application/json" \
  -d '{"condition": {"genome": "mm10", "agClass": "Histone", "agSubClass": "H3K4me3", "clClass": "Pluripotent stem cell", "qval": "5"}}'
```

---

## 6. Scenario 4: Check Available Analyses

**Question:** *"What colocalization and target gene analyses are available?"*

### With MCP tools

```
chipatlas_get_colocalization(genome="hg38")
```

Expected: Returns which antigen/cell type combinations have precomputed colocalization results for hg38.

```
chipatlas_get_target_genes()
```

Expected: Returns a mapping of genomes to lists of antigens with precomputed target gene data.

### With HTTP API (curl)

```bash
# Colocalization index
curl "https://chip-atlas.org/data/colo_analysis.json?genome=hg38"

# Target genes index
curl "https://chip-atlas.org/data/target_genes_analysis.json"
```

---

## 7. Scenario 5: Research Workflow

**Question:** *"I'm studying gene regulation in liver cancer. What epigenomic data can help me?"*

This scenario chains multiple tools in a realistic research context. Here's how an agent would approach it:

**Step 1** — Find what data exists for liver:

```
chipatlas_list_experiment_types(genome="hg38", clClass="Liver")
chipatlas_list_sample_types(genome="hg38", agClass="TFs and others")
```

**Step 2** — Explore transcription factors in liver:

```
chipatlas_list_antigens(genome="hg38", agClass="TFs and others", clClass="Liver")
```

**Step 3** — Search for liver cancer cell lines:

```
chipatlas_search_experiments(query="HepG2")
chipatlas_list_cell_types(genome="hg38", agClass="TFs and others", clClass="Liver")
```

**Step 4** — Check if target gene analysis is available:

```
chipatlas_get_target_genes()
```

**Step 5** — Get peak data for a key factor:

```
chipatlas_get_bed_url(
  genome="hg38",
  agClass="TFs and others",
  agSubClass="HNF4A",
  clClass="Liver",
  qval="5"
)
```

The agent would synthesize all results into a summary of available data, relevant cell lines, key transcription factors, and downloadable datasets for liver cancer research.

---

## 8. HTTP API Cheat Sheet

**List genomes** — GET

```bash
curl https://chip-atlas.org/data/list_of_genome.json
```

**List experiment types** — GET

```bash
curl https://chip-atlas.org/data/list_of_experiment_types.json
```

**Experiment types with counts** — GET

```bash
curl "https://chip-atlas.org/data/experiment_types?genome=hg38&clClass=Blood"
```

**Sample types with counts** — GET

```bash
curl "https://chip-atlas.org/data/sample_types?genome=hg38&agClass=Histone"
```

**List antigens** — GET

```bash
curl "https://chip-atlas.org/data/chip_antigen?genome=hg38&agClass=Histone&clClass=Blood"
```

**List cell types** — GET

```bash
curl "https://chip-atlas.org/data/cell_type?genome=hg38&agClass=Histone&clClass=Blood"
```

**Search experiments** — GET

```bash
curl "https://chip-atlas.org/data/search_experiments?query=CTCF&limit=5"
```

**Experiment metadata** — GET

```bash
curl "https://chip-atlas.org/data/exp_metadata.json?expid=SRX018625"
```

**Colocalization index** — GET

```bash
curl "https://chip-atlas.org/data/colo_analysis.json?genome=hg38"
```

**Target genes index** — GET

```bash
curl https://chip-atlas.org/data/target_genes_analysis.json
```

**Download BED URL** — POST

```bash
curl -X POST https://chip-atlas.org/download \
  -H "Content-Type: application/json" \
  -d '{"condition": {"genome": "hg38", "agClass": "Histone"}}'
```

---

## 9. Tips & Troubleshooting

**General tips:**

- **Start with `chipatlas_list_genomes`** if you're unsure which genome to use.
- **agClass values are fixed strings:** "Histone", "TFs and others", "RNA polymerase", "Input control", "ATAC-Seq", "DNase-seq", "Bisulfite-Seq".
- **clClass values are case-sensitive.** Use `chipatlas_list_sample_types` to discover valid values rather than guessing.
- **Q-value** controls peak-call stringency: lower = stricter. Use 5 or 10 as reasonable defaults.
- **BED file URLs** point to potentially large files. Present them to the user rather than downloading directly.

**MCP troubleshooting:**

- **"Server not found"** — Check that the path in your config points to the built `dist/index.js` file. Run `npm run build` if it's missing.
- **"Connection refused"** — Restart your MCP client after updating the config.
- **Slow first search** — `search_experiments` loads a dataset on first call. Subsequent searches are fast. Prefer browsing tools (`list_antigens`, `list_cell_types`) when you know the classification.
- **Empty results** — Verify parameter values are exact matches. Use browsing tools to discover valid values before searching.

**HTTP API troubleshooting:**

- **URL encoding** — Spaces in parameter values (e.g. "All cell types", "TFs and others") must be URL-encoded (`%20` or `+`).
- **POST /download** — Requires a JSON body with a `condition` object, not query parameters.
- **CORS** — The API supports cross-origin requests for browser-based agents.

---

## Next Steps

- Read the full [Agent Guide](/agents) for complete tool reference and data model documentation
- View the [OpenAPI spec](/openapi.yaml) for machine-readable API details
- Browse the [MCP server source](https://github.com/inutano/chip-atlas/tree/master/mcp) on GitHub
- Check [.well-known/mcp.json](/.well-known/mcp.json) for auto-discovery metadata
