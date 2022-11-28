# ChIP-Atlas data in RDF

- Peak call data
- Target gene analysis
- Colocalization analysis

## Models

### Peaks

Peak data (bed files) are converted to the RDF triples with FALDO which enables to record the genomic location.

![model](images/chipatlas_bindingsites_rdf.png)

### Target genes and Colocalization

- Target genes
  - A class named `PutativeRegulation` is for pairs of transcription factors and their target genes candidates
  - The pairs have scores in respective distances from TSS (1k, 5k, 10k)
- Colocalization
  - A class named `Colocalization` is for pairs of transcription factors and their colocalization partner TFs
  - The Colo score means the strength of each peaks of the pair. See details [here](https://github.com/inutano/chip-atlas/wiki#colocalization_doc)

![analysis model](images/chipatlas_analysis_rdf.png)


## Usage

To test the RDF generation and get a tiny RDF example (S. cerevisiae):

```
$ git clone https://github.com/inutano/chip-atlas
$ cd chip-atlas/rdf
$ ./generate-rdf test
```

To get all RDF data (requires -1TB storage):

```
$ ./generate-rdf
```

The script is a wrapper for two gawk scripts work like below:

```
$ cd chip-atlas/rdf
$ curl "https://chip-atlas.dbcls.jp/data/sacCer3/allPeaks_light/allPeaks_light.sacCer3.50.bed.gz" | gunzip -c | gawk ./bin/chr2genbank -v ref=$(pwd)/reference -v genome_version=sacCer3 | gawk ./bin/bed2ttl -v data_version=test
```

How it works:

1. Download assembled peak call data
  - Details and links to files are at https://github.com/inutano/chip-atlas/wiki#downloads_doc
  - The table below "Download the lighter version of all peak-call data"
2. `chr2genbank` modifies chromosome name in the bed files according to the assembly reports saved in `reference`
  - need to specify the path to `reference` directory via `ref`
  - need to specify the genome version from hg19, mm9, rn6, dm3, ce10, or sacCer3
3. `bed2ttl` generates the RDF-Turtle format data according to the model above from the given bed file
  - need to specify the version name of RDF data: md5 checksum and date are used in the `generate-rdf` script
