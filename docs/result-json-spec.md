# Secondary Analysis Result JSON Specification

Defines the JSON output format for colocalization and target genes analysis results.
The pipeline v2 generates these files; the web app serves them via `/api/colo` and `/api/target_genes`.

**Date:** 2026-05-10
**Status:** Agreed — frontend will render these, pipeline v2 will generate them.

---

## Colocalization Result

**File naming:** `{track}.{cell_type}.json` (e.g., `CTCF.Neural.json`)
**Served at:** `GET /api/colo?genome=hg38&track=CTCF&cell_type=Neural`
**Hosted at:** `https://chip-atlas.dbcls.jp/data/{genome}/colo/{track}.{cell_type}.json`

### Structure

```json
{
  "genome": "hg38",
  "track": "CTCF",
  "cell_type": "Neural",
  "partners": [
    {
      "experiment_id": "SRX789012",
      "track": "RAD21",
      "cell_type": "HeLa",
      "cell_type_class": "Epithelial",
      "score": 7.23,
      "shared_bins": 15420
    }
  ]
}
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `genome` | string | Genome assembly (e.g., `hg38`, `mm10`) |
| `track` | string | Query track (antigen/factor name) |
| `cell_type` | string | Query cell type class |
| `partners` | array | Colocalization partners, sorted by `score` descending |
| `partners[].experiment_id` | string | SRX accession of partner experiment |
| `partners[].track` | string | Partner track (antigen/factor name) |
| `partners[].cell_type` | string | Partner cell type (specific) |
| `partners[].cell_type_class` | string | Partner cell type class (grouping) |
| `partners[].score` | float | Colocalization score (higher = stronger colocalization) |
| `partners[].shared_bins` | int | Number of 1kb genomic bins shared between query and partner |

### Notes

- Partners are pre-sorted by `score` descending.
- The `score` is derived from peak overlap patterns across shared genomic bins.
- Future extension: a `pair_counts` object (`{"H-H": n, "H-M": n, ...}`) may be added per partner for detailed overlap breakdown. The frontend does not require it for initial rendering.

---

## Target Genes Result

**File naming:** `{track}.{distance}.json` (e.g., `CTCF.5.json`)
**Served at:** `GET /api/target_genes?genome=hg38&track=CTCF&distance=5`
**Hosted at:** `https://chip-atlas.dbcls.jp/data/{genome}/target/{track}.{distance}.json`

### Structure

```json
{
  "genome": "hg38",
  "track": "CTCF",
  "distance": "5",
  "experiments": [
    {
      "experiment_id": "SRX123456",
      "cell_type": "HeLa",
      "cell_type_class": "Epithelial"
    },
    {
      "experiment_id": "SRX789012",
      "cell_type": "K-562",
      "cell_type_class": "Blood"
    }
  ],
  "genes": [
    {
      "symbol": "MYC",
      "avg_score": 842.3,
      "scores": [1200.5, 484.1]
    },
    {
      "symbol": "TP53",
      "avg_score": 721.0,
      "scores": [650.2, 791.8]
    }
  ]
}
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `genome` | string | Genome assembly |
| `track` | string | Query track (antigen/factor name) |
| `distance` | string | Window size from TSS in kb (`"1"`, `"5"`, or `"10"`) |
| `experiments` | array | List of experiments contributing to the analysis |
| `experiments[].experiment_id` | string | SRX accession |
| `experiments[].cell_type` | string | Specific cell type |
| `experiments[].cell_type_class` | string | Cell type class (grouping) |
| `genes` | array | Target genes, sorted by `avg_score` descending |
| `genes[].symbol` | string | Gene symbol (e.g., `MYC`, `TP53`) |
| `genes[].avg_score` | float | Average peak score across all experiments (0 for missing) |
| `genes[].scores` | array of float | Per-experiment peak scores, same order as `experiments[]` |

### Notes

- `genes[].scores` is a parallel array to `experiments[]` — index 0 in `scores` corresponds to index 0 in `experiments`.
- `avg_score` = sum of all scores / number of experiments (including 0 for experiments with no peak near the gene).
- Genes are pre-sorted by `avg_score` descending.
- The `distance` values are `"1"` (±1kb), `"5"` (±5kb), `"10"` (±10kb) from TSS.

---

## Download Formats

Both analysis types support file downloads via the app:

**Colocalization:**
- `GET /api/colo/download?genome=hg38&track=CTCF&cell_type=Neural&format=tsv` — tab-separated table of partners
- `GET /api/colo/download?genome=hg38&track=CTCF&cell_type=Neural&format=gml` — GML network graph

**Target Genes:**
- `GET /api/target_genes/download?genome=hg38&track=CTCF&distance=5&format=tsv` — tab-separated gene × experiment matrix

The download endpoints proxy files from the data server. The pipeline generates both JSON and TSV/GML formats.

---

## Conventions

- All field names use **snake_case**.
- Arrays are sorted by score descending (highest first).
- String values for `distance` (not integer) to match URL query parameter convention.
- The top-level fields echo the query parameters so the frontend can display context without URL parsing.
