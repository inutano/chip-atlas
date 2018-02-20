# ChIP-Atlas

ChIP-Atlas is the database of the processed data and analysis results of the public ChIP-Seq/DNase-Seq data archived in Sequence Read Archive (SRA). It also provides online data analysis function based on ChIP-Atlas's peak-call database. This repository contains the code of the web application and the documentation of the database.

### Web application

ChIP-Atlas is providing its full features on [chip-atlas.org](http://chip-atlas.org).

#### *in silico* ChIP

ChIP-Atlas is providing online enrichment analysis feature on [ChIP-Atlas - *in silico* ChIP](http://chip-atlas.org/in_silico_chip). The feature is based on the [NIG supercomputer system](http://sc.ddbj.nig.ac.jp), hosted by [DNA Data Bank of Japan, National Institute of Genetics](http://ddbj.nig.ac.jp). The feature depends on the computational resources provided by this shared computing cluster while the web application itself is running on the cloud, thus *in silico* ChIP may go down during the maintenance of the platform.

### Data availability

Processed data including the peak-call data in bed, bigBed or bigWig format is available to download via web application interface ([example](http://chip-atlas.org/view?id=SRX018625)). We also offer the bulk download of the data via [LSDB Archive](http://dx.doi.org/10.18908/lsdba.nbdc01558-000). We provide individual data for each experiment and data assembled by the curated metadata. See more details about downloading data in [Wiki](https://github.com/inutano/chip-atlas/wiki#downloads_doc).

### Sequencing quality information

Each individual data entry has its sequencing quality data imported from [Quanto project](https://github.com/inutano/sra-quanto), which calculated sequencing quality of data submitted to Sequence Read Archive by [FastQC](http://www.bioinformatics.babraham.ac.uk/projects/fastqc/).

### Citation

The ChIP-Atlas paper is now available on bioRxiv. You can also cite our database via the doi assigned to the data deposited in the National Bioscience Database Center.

- Preprint
  - Shinya Oki, Tazro Ohta, et al. Integrative analysis of transcription factor occupancy at enhancers and disease risk loci in noncoding genomic regions. bioRxiv 262899; doi: https://doi.org/10.1101/262899
- Website
  - Oki, S; Ohta, T (2015): ChIP-Atlas. http://chip-atlas.org
- Database
  - Oki, S; Ohta, T (2015): ChIP-Atlas. http://dx.doi.org/10.18908/lsdba.nbdc01558-000

### Contributors

- Shinya Oki, Kyushu University
  - Metadata curation
  - Workflow management and execution
- Tazro Ohta, Database Center for Life Science (DBCLS)
  - Development/Maintenance of web application
  - Development of data model
- Osamu Ogasawara, DNA Data Bank of Japan (DDBJ)
  - Support *in silico* ChIP implementation over [NIG supercomputer system](http://sc.ddbj.nig.ac.jp)
- Hideki Hatanaka, National Bioscience Database Center (NBDC)
  - Support data archive on [LSDB Archive](http://dbarchive.biosciencedbc.jp)

### Copyright

See LICENSE.txt for details of copyright of code provided under this repository. Copyright for the data can be browsed at the LSDB Archive website  [here](https://dbarchive.biosciencedbc.jp/en/chip-atlas/lic.html).
