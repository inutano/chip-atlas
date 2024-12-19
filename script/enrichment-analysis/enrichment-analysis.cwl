#!/usr/bin/env cwl-runner
class: CommandLineTool
cwlVersion: v1.0
hints:
  DockerRequirement:
    dockerPull: enrichment-analysis-app:latest
  http://commonwl.org/cwltool#LoadListingRequirement:
    loadListing:
      no_listing
requirements:
  InitialWorkDirRequirement:
    listing:
      - entry: $(inputs.tmpdir)
        writable: true
      - entry: $(inputs.outdir)
        writable: true
baseCommand: bash
arguments:
  - $(inputs.main_script)
  - $(inputs.bedAFile)
  - $(inputs.bedBFile)
  - $(inputs.typeA)
  - $(inputs.typeB)
  - $(inputs.descriptionA)
  - $(inputs.descriptionB)
  - $(inputs.title)
  - $(inputs.permTime)
  - $(inputs.distanceDown)
  - $(inputs.distanceUp)
  - $(inputs.genome)
  - $(inputs.antigenClass)
  - $(inputs.cellClass)
  - $(inputs.threshold)
  - $(inputs.wabiID)
  - $(inputs.expL)
  - $(inputs.fileL)
  - $(inputs.id2gene_dir)
  - $(inputs.uniqueTSS_dir)
  - $(inputs.chromSizes_dir)
  - $(inputs.referenceBed_dir)
  - $(inputs.btbpToHtml)
  - $(inputs.tmpdir)
  - $(inputs.outdir)
inputs:
  - id: main_script
    type: File
    default:
      class: File
      location: ./enrichment-analysis.sh
  - id: bedAFile
    type: string
  - id: bedBFile
    type: string
  - id: typeA
    type:
      type: enum
      symbols:
        - gene
        - bed
  - id: typeB
    type:
      type: enum
      symbols:
        - rnd
        - bed
        - refseq
        - userlist
  - id: descriptionA
    type: string
  - id: descriptionB
    type: string
  - id: title
    type: string
  - id: permTime
    type: int
  - id: distanceDown
    type: int
  - id: distanceUp
    type: int
  - id: genome
    type: string
  - id: antigenClass
    type: string
  - id: cellClass
    type: string
  - id: threshold
    type: int
  - id: wabiID
    type: string
  - id: expL
    type: File
  - id: fileL
    type: File
  - id: id2gene_dir
    type: Directory
  - id: uniqueTSS_dir
    type: Directory
  - id: chromSizes_dir
    type: Directory
  - id: referenceBed_dir
    type: Directory
  - id: btbpToHtml
    type: File
  - id: tmpdir
    type: Directory
  - id: outdir
    type: Directory
outputs:
  - id: output_dir
    type: Directory
    outputBinding:
      glob: $(inputs.outdir.path)/$(inputs.wabiID)
