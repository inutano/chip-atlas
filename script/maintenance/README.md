# Maintenance Scripts

Scripts for monitoring and testing ChIP-Atlas instances.

## check_wabi.sh

Verifies the DDBJ WABI backend is operational by checking the health endpoint, submitting a test enrichment analysis job, waiting for completion, and confirming results are retrievable.

```bash
./check_wabi.sh            # default timeout 600s
./check_wabi.sh -t 300     # custom timeout
./check_wabi.sh -q         # quiet mode (failures + final status only)
```

Exit code: `0` = WABI is up, `1` = failure detected.

### Checks

| # | Check | What it verifies |
|---|-------|------------------|
| 1 | Health endpoint | `GET /wabi/chipatlas/` returns `chipatlas` |
| 2 | Job submission | POST enrichment analysis job, receive `requestId` |
| 3 | Job completion | Poll until SLURM status is `COMPLETED` |
| 4 | TSV retrieval | Result data is non-empty and error-free |
| 5 | Log retrieval | Job log is non-empty and error-free |

## smoke_test.sh

End-to-end smoke test for a running ChIP-Atlas instance. Tests all major pages, APIs, form submissions, and WABI integration using sacCer3 (yeast) genome for minimal data and fast execution.

```bash
./smoke_test.sh                        # test localhost:9292
./smoke_test.sh http://13.231.231.30   # test a specific instance
```

Exit code: `0` = all passed, `1` = failures detected.

### Coverage

| # | Test | Endpoint | Method |
|---|------|----------|--------|
| 1 | Top page | `/` | GET |
| 2 | Health | `/health` | GET |
| 3 | Peak browser page | `/peak_browser` | GET |
| 4 | Colocalization page | `/colo` | GET |
| 5 | Target genes page | `/target_genes` | GET |
| 6 | Enrichment analysis page | `/enrichment_analysis` | GET |
| 7 | Diff analysis page | `/diff_analysis` | GET |
| 8 | Publications page | `/publications` | GET |
| 9 | WABI endpoint status | `/wabi_endpoint_status` | GET |
| 10 | Experiment types API | `/data/experiment_types` | GET |
| 11 | Sample types API | `/data/sample_types` | GET |
| 12 | Chip antigen API | `/data/chip_antigen` | GET |
| 13 | Q-value range API | `/qvalue_range` | GET |
| 14 | Full-text search | `/search` | GET |
| 15 | Peak browser: browse | `/browse` | POST |
| 16 | Peak browser: download | `/download` | POST |
| 17 | Colocalization: submit | `/colo?type=submit` | POST |
| 18 | Colocalization: TSV | `/colo?type=tsv` | POST |
| 19 | Target genes: submit | `/target_genes?type=submit` | POST |
| 20 | Target genes: TSV | `/target_genes?type=tsv` | POST |
| 21 | EA job submission | `/wabi_chipatlas` | POST |
| 22 | EA job polling | `/wabi_chipatlas?id=<id>` | GET |
