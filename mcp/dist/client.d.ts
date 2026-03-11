export declare class ChipAtlasClient {
    private baseUrl;
    constructor(baseUrl?: string);
    private fetchJson;
    private postJson;
    listGenomes(): Promise<string[]>;
    listExperimentTypes(genome?: string, clClass?: string): Promise<{
        id: string;
        label: string;
        count?: number;
    }[]>;
    listSampleTypes(genome: string, agClass: string): Promise<{
        id: string;
        label: string;
        count: number;
    }[]>;
    listAntigens(genome: string, agClass: string, clClass?: string): Promise<{
        id: string;
        label: string;
        count: number | null;
    }[]>;
    listCellTypes(genome: string, agClass: string, clClass?: string): Promise<{
        id: string;
        label: string;
        count: number | null;
    }[]>;
    searchExperiments(query: string, limit?: number, genome?: string): Promise<{
        total: number;
        returned: number;
        experiments: Record<string, string>[];
    }>;
    getExperiment(expid: string): Promise<Record<string, unknown>[]>;
    getColocalization(genome: string): Promise<Record<string, unknown>>;
    getTargetGenes(): Promise<Record<string, string[]>>;
    getBedUrl(condition: {
        genome: string;
        agClass: string;
        agSubClass?: string;
        clClass?: string;
        clSubClass?: string;
        qval?: string;
    }): Promise<{
        url: string;
    }>;
}
