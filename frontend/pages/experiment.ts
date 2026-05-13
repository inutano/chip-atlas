// frontend/pages/experiment.ts
// Builds the four action dropdowns (Visualize, Analyze, Download, Link Out)
// for the experiment detail page. Reads experiment records from a JSON island.

import type { ExperimentRecord } from '../api/client'

interface PageData {
  expid: string
  records: ExperimentRecord[]
}

const DATA_BASE = 'https://chip-atlas.dbcls.jp/data'
const IGV_BASE = 'http://localhost:60151/load?file=https://chip-atlas.dbcls.jp/data'
const QVALS = ['05', '10', '20'] as const
const TSS_KB = ['1', '5', '10'] as const

function readData(): PageData | null {
  const el = document.getElementById('experiment-data')
  if (!el || !el.textContent) return null
  try {
    return JSON.parse(el.textContent) as PageData
  } catch (err) {
    console.error('Failed to parse experiment-data:', err)
    return null
  }
}

function sanitize(s: string): string {
  return s.replace(/[^a-zA-Z0-9_-]/g, '_')
}

function header(text: string): HTMLLIElement {
  const li = document.createElement('li')
  const h = document.createElement('h6')
  h.className = 'dropdown-header'
  h.textContent = text
  li.appendChild(h)
  return li
}

function divider(): HTMLLIElement {
  const li = document.createElement('li')
  const hr = document.createElement('hr')
  hr.className = 'dropdown-divider'
  li.appendChild(hr)
  return li
}

function item(href: string, label: string, opts: { download?: string; external?: boolean } = {}): HTMLLIElement {
  const li = document.createElement('li')
  const a = document.createElement('a')
  a.className = 'dropdown-item'
  a.href = href
  a.textContent = label
  if (opts.download) a.setAttribute('download', opts.download)
  if (opts.external) {
    a.target = '_blank'
    a.rel = 'noopener noreferrer'
  }
  li.appendChild(a)
  return li
}

function igvName(record: ExperimentRecord, suffix: string): string {
  const base = `${record.track_subclass} (@ ${record.cell_type_subclass}) ${record.experiment_id}${suffix}`.replace(/, /g, '_')
  return encodeURIComponent(base)
}

function buildVisualizeMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  const isBisulfite = data.records[0].track_class === 'Bisulfite-Seq'

  data.records.forEach((record, i) => {
    items.push(header(`For ${record.genome}`))
    const g = record.genome
    const expid = data.expid

    if (!isBisulfite) {
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bw/${expid}.bw&genome=${g}&name=${igvName(record, '')}`,
        'BigWig',
      ))
      for (const q of QVALS) {
        items.push(item(
          `${IGV_BASE}/${g}/eachData/bb${q}/${expid}.${q}.bb&genome=${g}&name=${igvName(record, ` (1E-${q})`)}`,
          `Peak-call (q < 1E-${q})`,
        ))
      }
    } else {
      const cl = record.cell_type_subclass
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/methyl/${expid}.methyl.bw&genome=${g}&name=${encodeURIComponent(`Methylation rate (@ ${cl}) ${expid}`)}`,
        'BigWig (Methylation rate)',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/cover/${expid}.cover.bw&genome=${g}&name=${encodeURIComponent(`Coverage rate (@ ${cl}) ${expid}`)}`,
        'BigWig (Coverage)',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/hmr/BigBed/${expid}.hmr.bb&genome=${g}&name=${encodeURIComponent(`Hypo MR (@ ${cl}) ${expid}`)}`,
        'Hypo MR',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/pmd/BigBed/${expid}.pmd.bb&genome=${g}&name=${encodeURIComponent(`Partial MR (@ ${cl}) ${expid}`)}`,
        'Partial MR',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/hypermr/BigBed/${expid}.hypermr.bb&genome=${g}&name=${encodeURIComponent(`Hyper MR (@ ${cl}) ${expid}`)}`,
        'Hyper MR',
      ))
    }
    if (i < data.records.length - 1) items.push(divider())
  })
  return items
}

function buildAnalyzeMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  data.records.forEach((record, i) => {
    items.push(header(`For ${record.genome}`))
    items.push(item(`${DATA_BASE}/${record.genome}/colo/${data.expid}.html`, 'Colocalization'))
    for (const kb of TSS_KB) {
      items.push(item(`${DATA_BASE}/${record.genome}/target/${data.expid}.${kb}.html`, `Target Genes (TSS ± ${kb}kb)`))
    }
    if (i < data.records.length - 1) items.push(divider())
  })
  return items
}

function buildDownloadMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  const isBisulfite = data.records[0].track_class === 'Bisulfite-Seq'

  data.records.forEach((record, i) => {
    items.push(header(`For ${record.genome}`))
    const g = record.genome
    const expid = data.expid
    const fname = `${g}_${sanitize(record.track_subclass)}_${sanitize(record.cell_type_subclass)}_${expid}`

    if (!isBisulfite) {
      items.push(item(`${DATA_BASE}/${g}/eachData/bw/${expid}.bw`, 'BigWig', { download: `${fname}.bw` }))
      for (const q of QVALS) {
        items.push(item(
          `${DATA_BASE}/${g}/eachData/bed${q}/${expid}.${q}.bed`,
          `Peak-call (q < 1E-${q})`,
          { download: `${fname}.${q}.bed` },
        ))
      }
    } else {
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/methyl/${expid}.methyl.bw`, 'BigWig (Methylation rate)'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/cover/${expid}.cover.bw`, 'BigWig (Coverage)'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/hmr/BigBed/${expid}.hmr.bb`, 'Hypo MR'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/pmd/BigBed/${expid}.pmd.bb`, 'Partial MR'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/hypermr/BigBed/${expid}.hypermr.bb`, 'Hyper MR'))
    }
    if (i < data.records.length - 1) items.push(divider())
  })
  return items
}

function buildLinkOutMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  const m = data.records[0]
  const expid = data.expid
  const antigen = m.track_subclass
  const celltype = m.cell_type_subclass

  const encExpid = encodeURIComponent(expid)
  items.push(header('Sequence Read Archive'))
  items.push(item(`https://ddbj.nig.ac.jp/search/entry/sra-experiment/${encExpid}`, 'DDBJ Search', { external: true }))
  items.push(item(`https://www.ncbi.nlm.nih.gov/sra/?term=${encExpid}`, 'NCBI SRA', { external: true }))
  items.push(item(`https://www.ebi.ac.uk/ena/browser/view/${encExpid}`, 'ENA', { external: true }))
  items.push(divider())

  items.push(header(`Antigen: ${antigen}`))
  items.push(item(`https://www.wikigenes.org/?search=${encodeURIComponent(antigen)}`, 'wikigenes', { external: true }))
  items.push(item(`http://pdbj.org/mine/search?query=${encodeURIComponent(antigen)}`, 'PDBj', { external: true }))
  items.push(divider())

  items.push(header(`Cell Type: ${celltype}`))
  items.push(item(`http://www.atcc.org/Search_Results.aspx?searchTerms=${encodeURIComponent(celltype)}`, 'ATCC', { external: true }))
  items.push(item(`https://www.ncbi.nlm.nih.gov/mesh/?term=${encodeURIComponent(celltype)}`, 'MeSH', { external: true }))
  items.push(item(`http://www2.brc.riken.jp/lab/cell/list.cgi?skey=${encodeURIComponent(celltype)}`, 'RIKEN BRC', { external: true }))

  if (m.genome === 'hg19' || m.genome === 'hg38') {
    items.push(divider())
    items.push(header('Variation'))
    items.push(item(`https://togovar.biosciencedbc.jp/?term=${encodeURIComponent(antigen)}`, 'TogoVar', { external: true }))
  }
  return items
}

function fill(menuId: string, children: HTMLElement[]): void {
  const ul = document.getElementById(menuId)
  if (!ul) return
  ul.replaceChildren(...children)
}

function init(): void {
  const data = readData()
  if (!data || data.records.length === 0) return
  fill('visualize-menu', buildVisualizeMenu(data))
  fill('analyze-menu', buildAnalyzeMenu(data))
  fill('download-menu', buildDownloadMenu(data))
  fill('linkout-menu', buildLinkOutMenu(data))
}

document.addEventListener('DOMContentLoaded', init)
