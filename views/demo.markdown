## Demo: Using ChIP-Atlas with AI Agents

This tutorial walks you through querying ChIP-Atlas using AI agents. You'll learn two integration methods — **llms.txt** and the **HTTP API** — through hands-on scenarios with real data.

**What is ChIP-Atlas?** A comprehensive database of over 1 million public ChIP-seq, ATAC-seq, DNase-seq, Bisulfite-seq, CUT&Tag, and CUT&RUN experiments across seven genome assemblies (hg38, mm10, rn6, dm6, ce11, sacCer3, TAIR10). All data is uniformly processed and classified by genome, track class, track subclass, cell type class, and cell type subclass.

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

## 2. The HTTP API

Every feature of ChIP-Atlas is available through a read-only JSON API under the `/api/` prefix — no setup, no authentication, just HTTP GET requests. Field names use snake_case; classification endpoints return `{id, label, count}` arrays.

Try it:

```bash
curl https://chip-atlas.org/api/genomes
```

For the complete endpoint reference, see the [Agent Guide](/agents) or the [OpenAPI spec](/openapi.yaml).

---

## 3. Scenario 1: Explore Available Data

**Question:** *"What histone modification data exists for human blood cells?"*

```bash
# Step 1: Track classes available for human blood, with counts
curl "https://chip-atlas.org/api/track_classes?genome=hg38&cell_type_class=Blood"

# Step 2: Histone marks in blood (track subclasses)
curl "https://chip-atlas.org/api/track_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood"

# Step 3: Blood cell subtypes
curl "https://chip-atlas.org/api/cell_type_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood"
```

Each returns an array of `{id, label, count}`, so the agent can see how many experiments exist for each option.

---

## 4. Scenario 2: Find Specific Experiments

**Question:** *"Find CTCF ChIP-seq experiments in K-562 cells"*

```bash
# Full-text search (paginated)
curl "https://chip-atlas.org/api/search?q=CTCF%20K-562&genome=hg38&limit=5"

# Detailed metadata for one experiment
curl "https://chip-atlas.org/api/experiment?experiment_id=SRX018625"
```

Search returns `{total, returned, experiments: [...]}`, where each experiment includes `experiment_id`, `genome`, `track_class`, `track_subclass`, `cell_type_class`, `cell_type_subclass`, `title`, and `attributes`.

---

## 5. Scenario 3: Download Peak-Call Data

**Question:** *"Get H3K4me3 peak data for mouse embryonic stem cells"*

```bash
# Step 1: Find the right cell type class for mouse histone data
curl "https://chip-atlas.org/api/cell_type_classes?genome=mm10&track_class=Histone"

# Step 2: Get the BED download URL
#   - use "-" for any unspecified subclass
#   - qval comes from /api/qval_range (05, 10, 20, 50)
curl "https://chip-atlas.org/api/download_url?genome=mm10&track_class=Histone&track_subclass=H3K4me3&cell_type_class=Pluripotent%20stem%20cell&cell_type_subclass=-&qval=05"
```

The response is `{"url": "..."}` pointing to the assembled BED file on the data backend. A combination with no precomputed file returns `{"url": null}`.

---

## 6. Scenario 4: Check Available Analyses

**Question:** *"What colocalization and target gene analyses are available?"*

```bash
# Colocalization index for a genome
curl "https://chip-atlas.org/api/colo_index?genome=hg38"

# Target genes index (all genomes)
curl "https://chip-atlas.org/api/target_genes_index"

# Then fetch a specific result:
curl "https://chip-atlas.org/api/colo?genome=hg38&track=CTCF&cell_type=K-562"
curl "https://chip-atlas.org/api/target_genes?genome=hg38&track=CTCF&distance=5"
```

Not every track / cell-type combination has precomputed results — check the index endpoints first.

---

## 7. Scenario 5: Research Workflow

**Question:** *"I'm studying gene regulation in liver cancer. What epigenomic data can help me?"*

This scenario chains several requests in a realistic research context:

```bash
# Step 1: What track classes exist for liver?
curl "https://chip-atlas.org/api/track_classes?genome=hg38&cell_type_class=Liver"

# Step 2: Transcription factors assayed in liver
curl "https://chip-atlas.org/api/track_subclasses?genome=hg38&track_class=TFs%20and%20others&cell_type_class=Liver"

# Step 3: Search for a liver cancer cell line
curl "https://chip-atlas.org/api/search?q=HepG2&genome=hg38&limit=10"

# Step 4: Is target-gene analysis available?
curl "https://chip-atlas.org/api/target_genes_index"

# Step 5: Download peak data for a key factor
curl "https://chip-atlas.org/api/download_url?genome=hg38&track_class=TFs%20and%20others&track_subclass=HNF4A&cell_type_class=Liver&cell_type_subclass=-&qval=05"
```

An agent would chain these and synthesize a summary of available data, relevant cell lines, key transcription factors, and downloadable datasets for liver cancer research.

---

## 8. HTTP API Cheat Sheet

```bash
# Genomes
curl https://chip-atlas.org/api/genomes

# Track classes (static list, or add ?genome=&cell_type_class= for counts)
curl https://chip-atlas.org/api/track_classes

# Cell type classes with counts
curl "https://chip-atlas.org/api/cell_type_classes?genome=hg38&track_class=Histone"

# Track subclasses (antigens) with counts
curl "https://chip-atlas.org/api/track_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood"

# Cell type subclasses with counts
curl "https://chip-atlas.org/api/cell_type_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood"

# Search experiments (paginated)
curl "https://chip-atlas.org/api/search?q=CTCF&genome=hg38&limit=5"

# Experiment metadata
curl "https://chip-atlas.org/api/experiment?experiment_id=SRX018625"

# Q-value range and target-gene distances
curl https://chip-atlas.org/api/qval_range
curl https://chip-atlas.org/api/target_genes_distances

# BED download URL
curl "https://chip-atlas.org/api/download_url?genome=hg38&track_class=Histone&track_subclass=H3K4me3&cell_type_class=Blood&cell_type_subclass=-&qval=05"

# Colocalization & target genes
curl "https://chip-atlas.org/api/colo_index?genome=hg38"
curl "https://chip-atlas.org/api/target_genes_index"
```

---

## 9. Tips & Troubleshooting

- **Start with `/api/genomes`** if you're unsure which genome to use.
- **`track_class` values are fixed strings:** "Histone", "TFs and others", "RNA polymerase", "Input control", "ATAC-Seq", "DNase-seq", "Bisulfite-Seq", "CUT&Tag", "CUT&RUN".
- **Classification values are case-sensitive.** Use the classification endpoints to discover valid values rather than guessing.
- **Q-value** controls peak-call stringency: lower = stricter. Use "05" or "10" as defaults; `/api/qval_range` lists valid values.
- **URL-encode** spaces in parameter values (e.g. "All cell types", "TFs and others") as `%20`.
- **`download_url` requires** `genome`, `track_class`, `track_subclass`, `cell_type_class`, `cell_type_subclass` (use `-` for unspecified), and `qval`. Other combinations return `{"url": null}`.
- **No precomputed result?** Colocalization and target-gene results exist only for some combinations — check the index endpoints first. A 404 means that combination has no data, not that the API is broken.

---

## Next Steps

- Read the full [Agent Guide](/agents) for the complete endpoint reference and data model.
- View the [OpenAPI spec](/openapi.yaml) for machine-readable API details.
- Quick reference: [llms.txt](/llms.txt).
