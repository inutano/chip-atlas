// frontend/api/client.ts
// Typed API client for ChIP-Atlas backend

// ===== Interfaces =====

export interface GenomeInfo {
  [genome: string]: string  // e.g. { "hg38": "Homo sapiens", "mm10": "Mus musculus" }
}

export interface Stats {
  total_experiments: number
  total_experiments_formatted: string
  by_genome: Record<string, number>
  by_track_class: Record<string, number>
}

export interface ClassificationItem {
  id: string
  label: string
  count: number | null
}

export interface ExperimentTypeItem {
  id: string
  label: string
}

export interface ExperimentRecord {
  experiment_id: string
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  title: string
  attributes: string
  read_info: string
  cell_type_subclass_info: string
}

export interface SearchResult {
  total: number
  returned: number
  experiments: ExperimentRecord[]
}

export type QvalRange = string[]

export interface BedSizes {
  [key: string]: number
}

export interface ColoIndex {
  [track: string]: string[]  // track -> cell_types
}

export interface TargetGenesIndex {
  [genome: string]: string[]  // genome -> tracks
}

export interface IgvUrlResponse {
  url: string
}

export interface DownloadUrlResponse {
  url: string
}

export interface ColoData {
  [key: string]: unknown
}

export interface TargetGenesData {
  [key: string]: unknown
}

export interface UrlCondition {
  genome: string
  track_class: string
  track_subclass?: string
  cell_type_class?: string
  cell_type_subclass?: string
  qval?: string
  track?: string
  cell_type?: string
  distance?: string
}

export interface JobSubmission {
  type: 'enrichment_analysis' | 'diff_analysis'
  params: Record<string, unknown>
}

export interface JobSubmitResult {
  backend: string
  job_id: string
}

export interface JobStatus {
  backend: string
  job_id: string
  status: string
  retry: boolean
}

export interface JobResult {
  backend: string
  job_id: string
  urls: Record<string, string>
}

export interface JobAvailability {
  backend: string | null
  available: boolean
}

export interface EstimatedTime {
  minutes: number | null
}

export interface HealthCheck {
  status: string
  checks: {
    database: string
    experiments: string
    database_error?: string
  }
}

export interface ServiceStatus {
  services: {
    data_server: 'ok' | 'down'
    wabi: 'ok' | 'down'
    wes: 'ok' | 'down' | 'not_checked'
  }
  features: {
    peak_browser: 'ok' | 'unavailable'
    colo: 'ok' | 'unavailable'
    target_genes: 'ok' | 'unavailable'
    search: 'ok'
    enrichment_analysis: 'ok' | 'ok (backup)' | 'unavailable'
    diff_analysis: 'ok' | 'unavailable'
  }
}

// ===== Error handling =====

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly statusText: string,
    public readonly body: string
  ) {
    super(`API error ${status}: ${statusText}`)
    this.name = 'ApiError'
  }
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init)
  if (!response.ok) {
    const body = await response.text()
    throw new ApiError(response.status, response.statusText, body)
  }
  return response.json() as Promise<T>
}

async function requestText(url: string, init?: RequestInit): Promise<string> {
  const response = await fetch(url, init)
  if (!response.ok) {
    const body = await response.text()
    throw new ApiError(response.status, response.statusText, body)
  }
  return response.text()
}

function qs(params: Record<string, string | number | undefined>): string {
  const entries = Object.entries(params)
    .filter((pair): pair is [string, string | number] => pair[1] !== undefined)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
  return entries.length > 0 ? `?${entries.join('&')}` : ''
}

// ===== Classification endpoints =====

export async function listGenomes(): Promise<GenomeInfo> {
  return request<GenomeInfo>('/api/genomes')
}

export async function getStats(): Promise<Stats> {
  return request<Stats>('/api/stats')
}

export async function listTrackClasses(
  genome: string,
  cellTypeClass?: string
): Promise<ClassificationItem[]> {
  return request<ClassificationItem[]>(
    '/api/track_classes' + qs({ genome, cell_type_class: cellTypeClass })
  )
}

export async function listAllTrackClasses(): Promise<ExperimentTypeItem[]> {
  return request<ExperimentTypeItem[]>('/api/track_classes')
}

export async function listCellTypeClasses(
  genome: string,
  trackClass: string
): Promise<ClassificationItem[]> {
  return request<ClassificationItem[]>(
    '/api/cell_type_classes' + qs({ genome, track_class: trackClass })
  )
}

export async function listTrackSubclasses(
  genome: string,
  trackClass: string,
  cellTypeClass?: string
): Promise<ClassificationItem[]> {
  return request<ClassificationItem[]>(
    '/api/track_subclasses' + qs({ genome, track_class: trackClass, cell_type_class: cellTypeClass })
  )
}

export async function listCellTypeSubclasses(
  genome: string,
  trackClass: string,
  cellTypeClass?: string
): Promise<ClassificationItem[]> {
  return request<ClassificationItem[]>(
    '/api/cell_type_subclasses' + qs({ genome, track_class: trackClass, cell_type_class: cellTypeClass })
  )
}

// ===== Data endpoints =====

export async function getGenomeIndex(): Promise<Record<string, unknown>> {
  return request<Record<string, unknown>>('/api/genome_index')
}

export async function getExperiment(experimentId: string): Promise<ExperimentRecord[]> {
  return request<ExperimentRecord[]>(
    '/api/experiment' + qs({ experiment_id: experimentId })
  )
}

export async function searchExperiments(
  query?: string,
  genome?: string,
  limit?: number,
  offset?: number
): Promise<SearchResult> {
  return request<SearchResult>(
    '/api/search' + qs({ q: query, genome, limit, offset })
  )
}

export async function getQvalRange(): Promise<QvalRange> {
  return request<QvalRange>('/api/qval_range')
}

export async function getBedSizes(): Promise<BedSizes> {
  return request<BedSizes>('/api/bed_sizes')
}

// ===== Analysis index endpoints =====

export async function getColoIndex(genome: string): Promise<ColoIndex> {
  return request<ColoIndex>('/api/colo_index' + qs({ genome }))
}

export async function getTargetGenesIndex(): Promise<TargetGenesIndex> {
  return request<TargetGenesIndex>('/api/target_genes_index')
}

export async function getTargetGenesDistances(): Promise<string[]> {
  return request<string[]>('/api/target_genes_distances')
}

// ===== URL generation endpoints =====

export async function getIgvUrl(condition: UrlCondition): Promise<IgvUrlResponse> {
  return request<IgvUrlResponse>('/api/igv_url', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ condition }),
  })
}

export async function getDownloadUrl(condition: UrlCondition): Promise<DownloadUrlResponse> {
  return request<DownloadUrlResponse>('/api/download_url', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ condition }),
  })
}

// ===== Colocalization data =====

export async function getColoData(
  genome: string,
  track: string,
  cellType: string
): Promise<ColoData> {
  return request<ColoData>(
    '/api/colo' + qs({ genome, track, cell_type: cellType })
  )
}

export async function downloadColoFile(
  genome: string,
  track: string,
  cellType: string,
  format: 'tsv' | 'gml'
): Promise<string> {
  return requestText(
    '/api/colo/download' + qs({ genome, track, cell_type: cellType, format })
  )
}

// ===== Target genes data =====

export async function getTargetGenesData(
  genome: string,
  track: string,
  distance: string
): Promise<TargetGenesData> {
  return request<TargetGenesData>(
    '/api/target_genes' + qs({ genome, track, distance })
  )
}

export async function downloadTargetGenesFile(
  genome: string,
  track: string,
  distance: string,
  format: 'tsv'
): Promise<string> {
  return requestText(
    '/api/target_genes/download' + qs({ genome, track, distance, format })
  )
}

// ===== Job endpoints =====

export async function checkJobAvailability(
  type: 'enrichment_analysis' | 'diff_analysis' = 'enrichment_analysis'
): Promise<JobAvailability> {
  return request<JobAvailability>('/jobs/available' + qs({ type }))
}

export async function submitJob(submission: JobSubmission): Promise<JobSubmitResult> {
  return request<JobSubmitResult>('/jobs/submit', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(submission),
  })
}

export async function getJobStatus(id: string, backend: string): Promise<JobStatus> {
  return request<JobStatus>(`/jobs/${encodeURIComponent(id)}/status` + qs({ backend }))
}

export async function getJobResult(id: string, backend: string): Promise<JobResult> {
  return request<JobResult>(`/jobs/${encodeURIComponent(id)}/result` + qs({ backend }))
}

export async function getJobLog(id: string, backend: string): Promise<string> {
  return requestText(`/jobs/${encodeURIComponent(id)}/log` + qs({ backend }))
}

export async function getEstimatedTime(
  ids: string[],
  analysis: 'dmr' | 'diffbind'
): Promise<EstimatedTime> {
  return request<EstimatedTime>('/jobs/estimated_time', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids, analysis }),
  })
}

// ===== Health / status endpoints =====

export async function healthCheck(): Promise<HealthCheck> {
  return request<HealthCheck>('/health')
}

export async function serviceStatus(): Promise<ServiceStatus> {
  return request<ServiceStatus>('/status')
}

// ===== Internal endpoints =====

export async function checkRemoteUrlStatus(url: string): Promise<string> {
  return requestText('/api/remote_url_status' + qs({ url }))
}
