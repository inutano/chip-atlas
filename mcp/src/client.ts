const DEFAULT_BASE_URL = "https://chip-atlas.org";

export class ChipAtlasClient {
  private baseUrl: string;

  constructor(baseUrl?: string) {
    this.baseUrl = (baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
  }

  private async fetchJson<T>(path: string, query?: Record<string, string>): Promise<T> {
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
    return res.json() as Promise<T>;
  }

  private async postJson<T>(path: string, body: unknown, query?: Record<string, string>): Promise<T> {
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
    return res.json() as Promise<T>;
  }

  // GET /data/list_of_genome.json
  async listGenomes(): Promise<string[]> {
    return this.fetchJson<string[]>("/data/list_of_genome.json");
  }

  // GET /data/list_of_experiment_types.json  (static list)
  // GET /data/experiment_types?genome&clClass  (with counts)
  async listExperimentTypes(
    genome?: string,
    clClass?: string,
  ): Promise<{ id: string; label: string; count?: number }[]> {
    if (genome && clClass) {
      return this.fetchJson("/data/experiment_types", { genome, clClass });
    }
    return this.fetchJson("/data/list_of_experiment_types.json");
  }

  // GET /data/sample_types?genome&agClass
  async listSampleTypes(
    genome: string,
    agClass: string,
  ): Promise<{ id: string; label: string; count: number }[]> {
    return this.fetchJson("/data/sample_types", { genome, agClass });
  }

  // GET /data/chip_antigen?genome&agClass&clClass
  async listAntigens(
    genome: string,
    agClass: string,
    clClass?: string,
  ): Promise<{ id: string; label: string; count: number | null }[]> {
    return this.fetchJson("/data/chip_antigen", {
      genome,
      agClass,
      clClass: clClass ?? "undefined",
    });
  }

  // GET /data/cell_type?genome&agClass&clClass
  async listCellTypes(
    genome: string,
    agClass: string,
    clClass?: string,
  ): Promise<{ id: string; label: string; count: number | null }[]> {
    return this.fetchJson("/data/cell_type", {
      genome,
      agClass,
      clClass: clClass ?? "undefined",
    });
  }

  // GET /data/ExperimentList.json — returns { data: string[][] }
  // We filter client-side and return a limited set
  async searchExperiments(
    query: string,
    limit: number = 20,
  ): Promise<{ total: number; returned: number; experiments: Record<string, string>[] }> {
    const raw = await this.fetchJson<{ data: string[][] }>("/data/ExperimentList.json");
    const q = query.toLowerCase();
    const matched = raw.data.filter((row) =>
      row.some((cell) => cell.toLowerCase().includes(q)),
    );
    const capped = matched.slice(0, limit);
    return {
      total: matched.length,
      returned: capped.length,
      experiments: capped.map((row) => ({
        srx: row[0] ?? "",
        sra: row[1] ?? "",
        geo: row[2] ?? "",
        genome: row[3] ?? "",
        agClass: row[4] ?? "",
        agSubClass: row[5] ?? "",
        clClass: row[6] ?? "",
        clSubClass: row[7] ?? "",
      })),
    };
  }

  // GET /data/exp_metadata.json?expid=X
  async getExperiment(expid: string): Promise<Record<string, unknown>[]> {
    return this.fetchJson("/data/exp_metadata.json", { expid });
  }

  // GET /data/colo_analysis.json?genome=X
  async getColocalization(genome: string): Promise<Record<string, unknown>> {
    return this.fetchJson("/data/colo_analysis.json", { genome });
  }

  // GET /data/target_genes_analysis.json
  async getTargetGenes(): Promise<Record<string, string[]>> {
    return this.fetchJson("/data/target_genes_analysis.json");
  }

  // POST /download
  async getBedUrl(condition: {
    genome: string;
    agClass: string;
    agSubClass?: string;
    clClass?: string;
    clSubClass?: string;
    qval?: string;
  }): Promise<{ url: string }> {
    return this.postJson("/download", { condition });
  }
}
