#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { ChipAtlasClient } from "./client.js";
const client = new ChipAtlasClient(process.env.CHIP_ATLAS_BASE_URL);
const server = new McpServer({
    name: "chipatlas",
    version: "0.1.0",
});
// 1. chipatlas_list_genomes
server.tool("chipatlas_list_genomes", "List all available genome assemblies in ChIP-Atlas (e.g. hg38, mm10, dm6)", {}, async () => {
    const genomes = await client.listGenomes();
    return { content: [{ type: "text", text: JSON.stringify(genomes, null, 2) }] };
});
// 2. chipatlas_list_experiment_types
server.tool("chipatlas_list_experiment_types", "List experiment types (e.g. Histone, TFs and others, ATAC-Seq). Optionally provide genome and cell type class to get counts.", {
    genome: z
        .string()
        .optional()
        .describe("Genome assembly (e.g. hg38, mm10). Required together with clClass to get counts."),
    clClass: z
        .string()
        .optional()
        .describe('Cell type class (e.g. "Blood", "Brain"). Use "All cell types" for all. Required with genome.'),
}, async ({ genome, clClass }) => {
    const types = await client.listExperimentTypes(genome, clClass);
    return { content: [{ type: "text", text: JSON.stringify(types, null, 2) }] };
});
// 3. chipatlas_list_sample_types
server.tool("chipatlas_list_sample_types", "List cell type classes with experiment counts for a given genome and experiment type.", {
    genome: z.string().describe("Genome assembly (e.g. hg38, mm10)"),
    agClass: z
        .string()
        .describe('Experiment/antigen class (e.g. "Histone", "TFs and others", "ATAC-Seq")'),
}, async ({ genome, agClass }) => {
    const types = await client.listSampleTypes(genome, agClass);
    return { content: [{ type: "text", text: JSON.stringify(types, null, 2) }] };
});
// 4. chipatlas_list_antigens
server.tool("chipatlas_list_antigens", "List antigens/subclasses (e.g. H3K4me3, CTCF) with counts for a given genome and experiment class.", {
    genome: z.string().describe("Genome assembly (e.g. hg38, mm10)"),
    agClass: z
        .string()
        .describe('Experiment/antigen class (e.g. "Histone", "TFs and others")'),
    clClass: z
        .string()
        .optional()
        .describe("Cell type class to filter by (e.g. \"Blood\"). Omit for all cell types."),
}, async ({ genome, agClass, clClass }) => {
    const antigens = await client.listAntigens(genome, agClass, clClass);
    return { content: [{ type: "text", text: JSON.stringify(antigens, null, 2) }] };
});
// 5. chipatlas_list_cell_types
server.tool("chipatlas_list_cell_types", "List cell type subclasses with counts for a given genome and experiment class.", {
    genome: z.string().describe("Genome assembly (e.g. hg38, mm10)"),
    agClass: z
        .string()
        .describe('Experiment/antigen class (e.g. "Histone", "TFs and others")'),
    clClass: z
        .string()
        .optional()
        .describe("Cell type class to filter by (e.g. \"Blood\"). Omit for all cell types."),
}, async ({ genome, agClass, clClass }) => {
    const cellTypes = await client.listCellTypes(genome, agClass, clClass);
    return { content: [{ type: "text", text: JSON.stringify(cellTypes, null, 2) }] };
});
// 6. chipatlas_search_experiments
server.tool("chipatlas_search_experiments", "Search ChIP-Atlas experiments by keyword using full-text search. Searches across all fields (SRX ID, GEO ID, genome, antigen, cell type, title, attributes). Returns ranked results up to `limit`.", {
    query: z
        .string()
        .describe("Search keyword (e.g. 'H3K4me3', 'HeLa', 'SRX123456', 'liver')"),
    genome: z
        .string()
        .optional()
        .describe("Filter by genome assembly (e.g. 'hg38', 'mm10'). Omit for all genomes."),
    limit: z
        .number()
        .int()
        .min(1)
        .max(100)
        .optional()
        .describe("Maximum number of results to return (default 20, max 100)"),
}, async ({ query, genome, limit }) => {
    const results = await client.searchExperiments(query, limit ?? 20, genome);
    return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
});
// 7. chipatlas_get_experiment
server.tool("chipatlas_get_experiment", "Get detailed metadata for a single experiment by its SRX or GSM ID.", {
    expid: z.string().describe("Experiment ID (e.g. SRX123456 or GSM123456)"),
}, async ({ expid }) => {
    const metadata = await client.getExperiment(expid);
    if (!metadata || (Array.isArray(metadata) && metadata.length === 0)) {
        return { content: [{ type: "text", text: `No experiment found for ID: ${expid}` }] };
    }
    return { content: [{ type: "text", text: JSON.stringify(metadata, null, 2) }] };
});
// 8. chipatlas_get_colocalization
server.tool("chipatlas_get_colocalization", "Get colocalization analysis data for a genome. Returns available antigens and cell types that have colocalization data.", {
    genome: z.string().describe("Genome assembly (e.g. hg38, mm10)"),
}, async ({ genome }) => {
    const data = await client.getColocalization(genome);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
});
// 9. chipatlas_get_target_genes
server.tool("chipatlas_get_target_genes", "Get target genes analysis availability. Returns a mapping of genome assemblies to lists of antigens that have target gene analysis data.", {}, async () => {
    const data = await client.getTargetGenes();
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
});
// 10. chipatlas_get_bed_url
server.tool("chipatlas_get_bed_url", "Get a download URL for peak-call BED data given filtering conditions.", {
    genome: z.string().describe("Genome assembly (e.g. hg38, mm10)"),
    agClass: z
        .string()
        .describe('Experiment/antigen class (e.g. "Histone", "TFs and others")'),
    agSubClass: z
        .string()
        .optional()
        .describe("Antigen subclass (e.g. \"H3K4me3\", \"CTCF\"). Omit for all."),
    clClass: z
        .string()
        .optional()
        .describe("Cell type class (e.g. \"Blood\"). Omit for all cell types."),
    clSubClass: z
        .string()
        .optional()
        .describe("Cell type subclass (e.g. \"K-562\"). Omit for all."),
    qval: z
        .string()
        .optional()
        .describe("Q-value threshold (e.g. \"1\", \"5\", \"10\", \"50\", \"100\"). Default depends on server."),
}, async ({ genome, agClass, agSubClass, clClass, clSubClass, qval }) => {
    const result = await client.getBedUrl({
        genome,
        agClass,
        agSubClass,
        clClass,
        clSubClass,
        qval,
    });
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// Start the server
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
});
//# sourceMappingURL=index.js.map