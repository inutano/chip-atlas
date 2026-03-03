const DEFAULT_BASE_URL = "https://chip-atlas.org";
export class ChipAtlasClient {
    baseUrl;
    constructor(baseUrl) {
        this.baseUrl = (baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    }
    async fetchJson(path, query) {
        const url = new URL(path, this.baseUrl);
        if (query) {
            for (const [k, v] of Object.entries(query)) {
                if (v !== undefined && v !== "") {
                    url.searchParams.set(k, v);
                }
            }
        }
        const res = await fetch(url.toString());
        if (!res.ok) {
            throw new Error(`HTTP ${res.status} ${res.statusText}: ${url.toString()}`);
        }
        return res.json();
    }
    async postJson(path, body, query) {
        const url = new URL(path, this.baseUrl);
        if (query) {
            for (const [k, v] of Object.entries(query)) {
                if (v !== undefined && v !== "") {
                    url.searchParams.set(k, v);
                }
            }
        }
        const res = await fetch(url.toString(), {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
        if (!res.ok) {
            throw new Error(`HTTP ${res.status} ${res.statusText}: ${url.toString()}`);
        }
        return res.json();
    }
    // GET /data/list_of_genome.json
    async listGenomes() {
        return this.fetchJson("/data/list_of_genome.json");
    }
    // GET /data/list_of_experiment_types.json  (static list)
    // GET /data/experiment_types?genome&clClass  (with counts)
    async listExperimentTypes(genome, clClass) {
        if (genome && clClass) {
            return this.fetchJson("/data/experiment_types", { genome, clClass });
        }
        return this.fetchJson("/data/list_of_experiment_types.json");
    }
    // GET /data/sample_types?genome&agClass
    async listSampleTypes(genome, agClass) {
        return this.fetchJson("/data/sample_types", { genome, agClass });
    }
    // GET /data/chip_antigen?genome&agClass&clClass
    async listAntigens(genome, agClass, clClass) {
        return this.fetchJson("/data/chip_antigen", {
            genome,
            agClass,
            clClass: clClass ?? "undefined",
        });
    }
    // GET /data/cell_type?genome&agClass&clClass
    async listCellTypes(genome, agClass, clClass) {
        return this.fetchJson("/data/cell_type", {
            genome,
            agClass,
            clClass: clClass ?? "undefined",
        });
    }
    // GET /data/search?q=...&limit=...&genome=... — server-side FTS5 search
    async searchExperiments(query, limit = 20, genome) {
        return this.fetchJson("/data/search", {
            q: query,
            limit: String(limit),
            genome,
        });
    }
    // GET /data/exp_metadata.json?expid=X
    async getExperiment(expid) {
        return this.fetchJson("/data/exp_metadata.json", { expid });
    }
    // GET /data/colo_analysis.json?genome=X
    async getColocalization(genome) {
        return this.fetchJson("/data/colo_analysis.json", { genome });
    }
    // GET /data/target_genes_analysis.json
    async getTargetGenes() {
        return this.fetchJson("/data/target_genes_analysis.json");
    }
    // POST /download
    async getBedUrl(condition) {
        return this.postJson("/download", { condition });
    }
}
//# sourceMappingURL=client.js.map