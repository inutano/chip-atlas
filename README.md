# ChIP-Atlas

[ChIP-Atlas](https://chip-atlas.org) is a database collecting the bed files calculated from the ChIP-Seq, DNase-Seq, ATAC-Seq, and Bisulfite-seq data archived in Sequence Read Archive (SRA). The database has a web interface to explore the analysis results from the calculated peak call data. This repository contains the webapp code and the documentation of the database.

## Downtime of Enrichment Analysis function

ChIP-Atlas is providing online enrichment analysis function on [ChIP-Atlas - Enrichment Analysis](https://chip-atlas.org/enrichment_analysis). The background calculation relies on the [NIG supercomputer system](http://sc.ddbj.nig.ac.jp), hosted by [DNA Data Bank of Japan, National Institute of Genetics](http://ddbj.nig.ac.jp), while the webapp is hosted on its own cloud instance. Therefore, Enrichment Analysis may go down during the maintenance of the NIG supercomputer system. We announce when the function goes down, but if you encountered any trouble other than that period, please inform us from the issue page.

## Data availability

Processed data including the peak-call data in bed, bigBed or bigWig format is available to download via web application interface ([example](http://chip-atlas.org/view?id=SRX018625)). We also provide the bulk download via [LSDB Archive](http://dx.doi.org/10.18908/lsdba.nbdc01558-000) maintained by the [National Bioscience Database Center](https://biosciencedbc.jp/en/). We provide individual bed/wig data for each experiment and data assembled by the curated metadata. See more details in [Wiki](https://github.com/inutano/chip-atlas/wiki#downloads_doc).

## Disclaimer

We use the google analytics to analyze the visitor information to improve our web service and report the summarized web access status to our funding agencies. The web server records the queries just for solving issues such as server error. We will not open or distribute those information without an announcement to the users.

## Citation

- Publication
  - Zou Z, Ohta T, Miura F, Oki S. ChIP-Atlas 2021 update: a data-mining suite for exploring epigenomic landscapes by fully integrating ChIP-seq, ATAC-seq and Bisulfite-seq data. Nucleic Acids Research. Oxford University Press (OUP); 2022. http://dx.doi.org/10.1093/nar/gkac199
  - Oki S, Ohta T, Shioi G, Hatanaka H, Ogasawara O, Okuda Y, Kawaji H, Nakaki R, Sese J, Meno C. ChIP‐Atlas: a data‐mining suite powered by full integration of public ChIP‐seq data. Vol. 19, EMBO reports. EMBO; 2018. http://dx.doi.org/10.15252/embr.201846255
- Website
  - Oki, S; Ohta, T (2015): ChIP-Atlas. http://chip-atlas.org
- Database
  - Oki, S; Ohta, T (2015): ChIP-Atlas. http://dx.doi.org/10.18908/lsdba.nbdc01558-000

## Contributors

- Shinya Oki, Kyoto University
  - Metadata curation
  - Workflow management and execution
- Tazro Ohta, Database Center for Life Science (DBCLS)
  - Development/Maintenance of web application
  - Development of data model
- Osamu Ogasawara, DNA Data Bank of Japan (DDBJ)
  - Support enrichment analysis implementation over [NIG supercomputer system](http://sc.ddbj.nig.ac.jp)
- Hideki Hatanaka, National Bioscience Database Center (NBDC)
  - Support data archive on [LSDB Archive](https://dbarchive.biosciencedbc.jp)

## Copyright

See LICENSE.txt for details of copyright of code provided under this repository. Copyright for the data can be browsed at the LSDB Archive website [here](https://dbarchive.biosciencedbc.jp/en/chip-atlas/lic.html).
