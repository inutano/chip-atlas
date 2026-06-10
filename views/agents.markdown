## ChIP-Atlas for AI Agents

ChIP-Atlas is a comprehensive database of public ChIP-seq, ATAC-seq, DNase-seq, Bisulfite-seq, CUT&Tag, and CUT&RUN experiments. This page describes how AI agents and scripts can query ChIP-Atlas programmatically via its HTTP API.

**New here?** Check out the [hands-on demo tutorial](/demo) for step-by-step scenarios you can try with your preferred LLM.

**Machine-readable spec:** [OpenAPI 3.1 (openapi.yaml)](/openapi.yaml) &middot; **Quick reference:** [llms.txt](/llms.txt)

---

## API Basics

- **Base URL:** `https://chip-atlas.org`
- All endpoints are under the `/api/` prefix, return JSON, and use **snake_case** field names.
- Read-only. No authentication required.
- Classification endpoints return arrays of `{id, label, count}` objects (`count` is `null` when not applicable). Search returns `{total, returned, experiments: [...]}`.

---

## Data Model

ChIP-Atlas organizes data along these dimensions:

| Dimension | Field | Examples |
|-----------|-------|----------|
| **Genome** | `genome` | hg38, mm10, rn6, dm6, ce11, sacCer3, TAIR10 |
| **Track class** | `track_class` | Histone, TFs and others, RNA polymerase, Input control, ATAC-Seq, DNase-seq, Bisulfite-Seq, CUT&Tag, CUT&RUN |
| **Track subclass** | `track_subclass` | H3K4me3, CTCF, p300 (the specific antigen/target) |
| **Cell type class** | `cell_type_class` | Blood, Brain, Liver, All cell types (broad category) |
| **Cell type subclass** | `cell_type_subclass` | K-562, HeLa, GM12878 (specific cell line/tissue) |
| **Q-value** | `qval` | 05, 10, 20, 50 (peak-call threshold; smaller = stricter) |

Experiments are identified by an SRX, ERX, or DRX accession ID (`experiment_id`). GEO sample IDs (GSM…) are accepted where noted.

---

## Endpoint Reference

### Classification — browse the hierarchy

Start broad and drill down. Each returns an array of `{id, label, count}`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/genomes` | Available genome assemblies (object: `id` → label) |
| GET | `/api/track_classes` | Static list of track classes; add `?genome=hg38&cell_type_class=Blood` for counts |
| GET | `/api/cell_type_classes?genome=hg38&track_class=Histone` | Cell type classes with counts |
| GET | `/api/track_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood` | Track subclasses (H3K4me3, CTCF, …) with counts |
| GET | `/api/cell_type_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood` | Cell type subclasses (K-562, …) with counts |

### Experiments

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/search?q=CTCF&genome=hg38&limit=20&offset=0` | Full-text search with pagination. Returns `{total, returned, experiments}` |
| GET | `/api/experiment?experiment_id=SRX018625` | Full metadata for one experiment |
| GET | `/api/stats` | Database totals and breakdowns by genome and track class |

### Analysis indexes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/colo_index?genome=hg38` | Which track / cell-type combinations have precomputed colocalization results |
| GET | `/api/target_genes_index` | Genomes → tracks with precomputed target-gene data |
| GET | `/api/target_genes_distances` | Valid distance options (1, 5, 10 kb) |
| GET | `/api/qval_range` | Valid q-value thresholds (05, 10, 20, 50) |

### Result data and downloads

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/download_url?genome=…&track_class=…&track_subclass=…&cell_type_class=…&cell_type_subclass=-&qval=05` | BED file download URL for a peak-call dataset |
| GET | `/api/igv_url?genome=…&track_class=…&…` | IGV genome-browser URL (same parameters as `download_url`) |
| GET | `/api/colo?genome=hg38&track=CTCF&cell_type=K-562` | Colocalization result data (JSON), proxied from the data backend |
| GET | `/api/colo/download?genome=hg38&track=CTCF&cell_type=K-562&format=tsv` | Download colocalization result (`format=tsv` or `gml`) |
| GET | `/api/target_genes?genome=hg38&track=CTCF&distance=5` | Target-gene result data (JSON) |
| GET | `/api/target_genes/download?genome=hg38&track=CTCF&distance=5&format=tsv` | Download target-gene result (tsv) |

For `download_url` / `igv_url`, supply `-` for any unspecified `track_subclass` / `cell_type_subclass`. A combination with no precomputed file returns `{"url": null}`.

### Jobs — enrichment & differential analysis

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/status` | Data server / compute backend availability |
| GET | `/jobs/available?type=enrichment_analysis` | Is a backend up for this job type? |
| POST | `/jobs/submit` | Submit an enrichment or differential analysis job |
| GET | `/jobs/:id/status?backend=wabi` | Poll job status |
| GET | `/jobs/:id/result?backend=wabi` | Result URLs for a finished job |
| GET | `/jobs/:id/log?backend=wabi` | Execution log |

---

## Common Workflows

### Discover what data exists for a genome

```
GET /api/genomes
GET /api/track_classes?genome=hg38&cell_type_class=Blood
GET /api/cell_type_classes?genome=hg38&track_class=Histone
```

### Search for specific experiments

```
GET /api/search?q=CTCF%20K-562&genome=hg38
GET /api/experiment?experiment_id=SRX018625
```

### Get a download URL for peak data

```
GET /api/track_subclasses?genome=hg38&track_class=Histone&cell_type_class=Blood
GET /api/download_url?genome=hg38&track_class=Histone&track_subclass=H3K4me3&cell_type_class=Blood&cell_type_subclass=-&qval=05
```

### Check available analyses

```
GET /api/target_genes_index
GET /api/colo_index?genome=hg38
```

---

## Tips

- **Start with `/api/genomes`** if the user hasn't specified a genome.
- **`track_class` values are fixed strings:** "Histone", "TFs and others", "RNA polymerase", "Input control", "ATAC-Seq", "DNase-seq", "Bisulfite-Seq", "CUT&Tag", "CUT&RUN". Use `/api/track_classes` to confirm.
- **Classification values are case-sensitive.** Use the classification endpoints to discover valid values rather than guessing.
- **Search is paginated** (`limit` ≤ 100, `offset`). It replaces the previous bulk JSON experiment dump.
- **Q-value** controls peak-call stringency: lower = stricter. "05" or "10" are reasonable defaults; `/api/qval_range` lists valid values.
- **Download and result URLs** point to potentially large files on the data backend (chip-atlas.dbcls.jp). Present them to the user rather than fetching them.
- **URL-encode** spaces in parameter values (e.g. "All cell types", "TFs and others") as `%20`.
