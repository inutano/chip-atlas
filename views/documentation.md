# ChIP-Atlas / Documentation

Documentation for computational processing in ChIP-Atlas.

## Table of Contents

1. [Data source](#data_source_doc)
2. [Primary processing](#primary_processing_doc)
3. [Data Annotation](#data_annotation_doc)
4. [Peak browser](#peak_browser_doc)
5. [Target genes](#target_genes_doc)
6. [Colocalization](#colocalization_doc)
7. [Virtual ChIP](#virtual_chip_doc)

<a id="data_source_doc"></a>

## 1. Data source

Currently, almost all of the academic journals require that authors studying with high throughput sequencer must submit their raw sequence data as SRAs (Sequence Read Archives) to public repositories ([NCBI][NCBI], [DDBJ][DDBJ] or [ENA][ENA]). Each experiment is assigned to an ID, called experimental accessions that begin with SRX, DRX or ERX (thereafter '[SRXs][SRX]' on behalf of them). Referring to corresponded 'experiment' and 'biosample' metadata in XML format (available from [NCBI FTP site][NCBImeta]), ChIP-Atlas used SRXs matching all of the following criteria:

- LIBRARY STRATEGY == "ChIP-seq" or "DNase-Hypersensitivity"
- LIBRARY_SOURCE == "GENOMIC"
- INSTRUMENT_MODEL ~ "Illumina"

![][dataNumber]

<a id="primary_processing_doc"></a>

## 2. Primary processing

### Introduction

Sequence raw data from SRXs shown above were aligned to reference genome with Bowtie2, before producing coverage data in BigWig format and peak-calls in BED format.  
![][flowchart]

### Methods

#### 1.

Binarized sequence raw data (.sra) for each SRX were downloaded and decoded into Fastq format with `fastq-dump` command of [SRA Toolkit][SraToolKit] (ver 2.3.2-4) with default mode unless paired-end reads, which were decoded with `--split-files` option. If the SRX includes multiple runs, decoded Fastq files were concatenated into single one.

#### 2.

Fastq files were then aligned with [Bowtie 2][bowtie2] (ver 2.2.2) with default mode unless paired-end reads, for which two Fastq files were specified with `-1` and `-2` options. Following genome assemblies were used for the alignment and processing thereafter:

- **hg19** (_H. sapiens_)
- **mm9** (_M. musculus_)
- **dm3** (_D. melanogaster_)
- **ce10** (_C. elegans_)
- **sacCer3** (_S. cerevisiae_)

#### 3.

Resultant SAM-formatted files were then binarized into BAM format with [SAMtools][samtools] (ver 0.1.19; `samtools view`) and sorted (`samtools sort`) before removing PCR duplicates (`samtools rmdup`).

#### 4.

BedGraph-formatted coverage scores were calculated with [bedtools][bedtools] (ver 2.17.0; `genomeCoverageBed`) in RPM (Reads Per Million mapped reads) units with `-scale 1000000/N` option, where N is the mapped read counts after removing PCR duplicates shown in former section (3).

#### 5.

BedGraph files were binarized into BigWig format with [UCSC][UCSCtools]  `bedGraphToBigWig` tool (ver 4). BAM files made in (3) were used to peak-call with [MACS2][MACS2] (ver 2.1.0; `macs2 callpeak`) in BED4 format. Options for _q_-value threshold were set (`-q 1e-05`, `1e-10` or `1e-20`), with the options for genome sizes being as follows:

- hg19: `-g hs`
- mm9: `-g mm`
- dm3: `-g dm`
- ce10: `-g ce`
- sacCer3: `-g 12100000`

Each row in the BED4 files includes genomic location at the 1st to 3rd columns and MACS2 score (-10*log*<sub>10</sub>[MACS2 *q*-value]) at the 4th column.

#### 6.

BED4 files were binarized into BigBed format with [UCSC][UCSCtools] `bedToBigBed` tool (ver 2.5).

<a id="data_annotation_doc"></a>

## 3. Data Annotation

### Introduction

Experimental materials used for each SRX were manually annotated, by which it is capable of extracting data matching with given keywords for antigens and cell types.

### Methods

#### 1.

Sample metadata for all SRXs (biosample_set.xml) were downloaded [NCBI FTP site][NCBImeta] to extract attributes described for antigens and antibodies ([Doc S1][Doc_S1]) and those for cell types and tissues ([Doc S2][Doc_S2]).

#### 2.

According to the attribute values described to each SRX, antigens and cell types used were manually annotated by curators who have been fully trained on molecular and developmental biology. Each annotation has 'Class' and 'Subclass' as shown in [Table S1][Table_S1].

#### 3.

Criteria for antigens annotation:

##### Histones

Based on Brno nomenclature ([PMID: 15702071][PMID_15702071]). (eg. H3K4me3, H3K27ac)

#### Gene-encoded proteins

Gene symbols were recorded according to the following gene nomenclature databases:

- [HGNC][HGNC] (*H. sapiens*)  
- [MGI][MGI] (*M. musculus*)
- [FlyBase][FlyBase] (*D. melanogaster*)
- [WormBase][WormBase] (*C. elegans*)
- [SGD][SGD] (*S. cerevisiae*)

(eg. OCT3/4 => POU5F1; p53 => TP53)

Modifications such as phosphorylation were ignored. (eg. phospho-SMAD3 => SMAD3)

If an antibody recognizes multiple family molecules, the top in ascending order was chosen. (eg. Anti-SMAD2/3 antibody => SMAD2)

#### 4.

Criteria for cell types annotation:

##### _H. sapiens_ and _M. musculus_

Cell types were mainly classified with derived tissues. ES and iPS cells were exceptionally classified in 'Pluripotent stem cell' class.

| Cell-type class       | Cell-type                        |
|:----------------------|:---------------------------------|
| Blood                 | K-562; CD4-Positive T-Lymphocytes|
| Breast                | MCF-7; T-47D                     |
| Pluripotent stem cell | hESC H1; iPS cells               |

##### _D. melanogaster_

Cell types were mainly classified with cell lines and developmental stages.

##### _C. elegans_

Mainly classified with developmental stages.

##### _S. cerevisiae_

Classified with yeast strains.

##### Standardized Nomenclatures

Nomenclatures of cell lines and tissue names were standardized according to those recorded in following frameworks and resources.

- Supplementary Table 2 in Yu et. al 2015 ([PMID: 25877200][PMID_25877200]), proposing unified cell-line names
- [ATCC], a nonprofit repository of cell lines
- [MeSH] \(Medical Subject Headings\) for tissue names
- [FlyBase] for cell lines of *D. melanogaster*
    (eg. MDA-231, MDA231, MDAMB231 => MDA-MB-231)

#### 5.

Antigens or cell types were classified in 'Uncategorized' class if the curators could not understand the meanings of attribute values.

#### 6.

Antigens or cell types were classified in 'No description' class if there was no attribute value.


<a id="peak_browser_doc"></a>

## 4. Peak browser

This section allows users to search the proteins that are bound to given genomic loci on genome browser IGV. This is useful to predict the cis-regulatory element as well as to know the regulatory proteins and epigenetic status on given regions. BED4-formatted peak-call data made in **2.5** were concatenated and converted to BED9 + GFF3 format to be browsed on genome browser IGV.

| Column     | Description                             | Example   |
|------------|-----------------------------------------|-----------|
| Header     | Track name and link URL                 | (Strings) |
| Column 1   | Chromosome                              | chr12     |
| Column 2   | Begin                                   | 1234      |
| Column 3   | End                                     | 5678      |
| Column 4*  | Sample metadata                         | (Strings) |
| Column 5   | -10*log*<sub>10</sub>(MACS2 *q*-value)  | 345       |
| Column 6   | .                                       | .         |
| Column 7   | Begin (= Column 2)                      | 1234      |
| Column 8   | End (= Column 3)                        | 5678      |
| Column 9** | Color code                              | 255,61,0  |

### Column 4

Sample metadata described in GFF3 format to show annotated antigens and cell types on IGV. Furthermore, mouse-overing a peak displays accession number, title and all attribute values described in Biosample metadata for the SRX.

### Column 9

Heatmap color codes for Column 5. (If Column 5 is 0, 500 or 1000, then the color is blue, green or red, respectively)

<a id="target_genes_doc"></a>

## 5. Target genes

### Introduction

This section predicts the genes directly regulated by given proteins, according to binding profiles of all the public ChIP-seq data to gene loci. Target genes were adopted if the peak-call intervals of a given protein overlapped with transcription start site (TSS) ± N kb (N = 1, 5 or 10).

### Methods

#### 1. Peak-call data

BED4-formatted peak-call data of each SRX made in section **2.5** were used (MACS2 *q*-value threshold = 1e-5; antigen class = 'TFs and others').

#### 2. Preparation of TSS library

Location of TSSs and gene symbols were according to refFlat files (at [UCSC FTP site][UCSC_FTP]), from which only protein-coding genes were used for this analysis.

#### 3. Preparation of STRING library

[STRING][STRING] is a comprehensive database recording protein-protein and protein-gene interactions from the experimental evidence. From this website, protein.actions.v10.txt.gz file describing all interactions were downloaded, and the protein IDs were converted to gene symbols with protein.aliases.v10.txt.gz file.

#### 4. Processing:

`bedtools window` command ([bedtools][bedtools] ver 2.17.0) was used to search target genes of a peak-call data (**5.1**) from the TSS library (**5.2**) with a window size option (`-w 1000`, `5000` or `10000`). Peak-call data of the same antigens were piled up, and MACS2 scores (-10*log*<sub>10</sub>[MACS2 *q*-value]) were indicated as heatmap colors on the web browser (MACS2 score = 0, 500, 1000 => color = blue, green, red). If a gene intersected with multiple peaks of single SRX, the highest MACS2 score was chosen for the color indication. The 'Average' column on the leftmost of the table is the means of the MACS2 scores in the same row. The 'STRING' column on the rightmost indicates the STRING scores for the protein-gene interaction according to STRING library (**5.3**). For the detail, protein-gene pairs in protein.actions.v10.txt.gz file were extracted if matching to following all conditions:

- 1st column (item\_id\_a) == Query antigen
- 2nd column (item\_id\_b) == Target gene
- 3rd column (mode) == "expression"
- 5th column (a\_is\_acting) == "1"

<a id="colocalization_doc"></a>

## 6. Colocalization

### Introduction

It is well known that several kinds of transcription factors (TFs) make a complex to exert arranged or strong transcriptional activity (eg. Pou5f1, Nanog and Sox2 in mouse ES cells). ChIP-seq profiles of such the TFs are quite similar, often showing colocalization on multiple genomic regions. This section predicts colocalization partners of given TFs, evaluated by comprehensive and combinatorial similarity analyses of all public ChIP-seq data.

### Algorithms

BED4-formatted peak-call data made in section **2.5** were analyzed to evaluate the similarities to other peak-call data in identical cell-type class. The similarity was evaluated with CoLo, a tool to evaluate the colocalization of transcription factors (TFs) with multiple ChIP-seq peak-call data. Advantages to use CoLo is that:

(**a**) it compensates the biases derived from different experimental conditions.  
(**b**) it adjusts the difference of the peak numbers and distributions coming from innate characteristics of the TFs.

The function (**a**) is programed so that MACS2 scores in each BED4 file were fitted to a Gaussian distribution, by which the BED4 file divided into following three groups:

- **H** (High binding; Z-score > 0.5)
- **M** (Middle binding; -0.5 ≤ Z-score ≤ 0.5)
- **L** (Low binding; Z-score < -0.5)

These three groups are used as the independent data to evaluate similarity through the function (**b**). Thus, CoLo evaluates the similarity of two SRXs (eg. SRX\_1 and SRX\_2) with nine combinations:  
[H/M/L of SRX\_1] x [H/M/L of SRX\_2]  
Eventually, a set of nine Boolean results (similar or not) is returned to indicate the similarity of SRX\_1 and SRX\_2.

### Methods

#### 1. Peak-call data: Same as (**5.1**).

#### 2. STRING library: Same as (**5.2**).

#### 3. Processing:

Peak-call data in an identical cell-type class were processed through CoLo. The scores between the two BED files were calculated by multiplication of the combination of the H (= 3), M (= 2) or L (= 1) as follows:

|SRX_1|SRX_2|Scores|
|:---:|:---:|:----:|
|H    |H    |9     |
|H    |M    |6     |
|H    |L    |3     |
|M    |H    |6     |
|M    |M    |4     |
|M    |L    |2     |
|L    |H    |3     |
|L    |M    |2     |
|L    |L    |1     |

If multiple H/M/L combinations were returned from SRX_1 and SRX_2, the highest score was adopted. The scores (1 to 9) were colored in blue, green to red, and colored in gray if all of the nine H/M/L combinations were false. The 'Average' column on the leftmost of the table is the means of the CoLo scores in the same row. The 'STRING' column on the rightmost indicates the STRING scores for the protein-protein interaction (**6.2**). For the detail, protein-protein pairs in protein.actions.v10.txt.gz file were extracted if matching to following all conditions:

- 1st column (item\_id\_a) == query antigen
- 2nd column (item\_id\_b) == coassociation partner
- 3rd column (mode) == "binding"

<a id="virtual_chip_doc"></a>

## 7. Virtual ChIP

### Introduction

This section accepts users' data in following three formats:

- ChIP-seq data in BED format (to search similar ChIP-seq data)
- Sequence motif (to search proteins bound to the motif)
- Gene list (to search proteins bound to the genes)

In addition, following analyses are applicable by specifying the data for comparison:

|My data|Compare with       |Aims and analyses                                                   |
|-------|-------------------|--------------------------------------------------------------------|
|BED    |Random permutation |Proteins bound to BED intervals more often than by chance.          |
|BED    |BED                |Proteins differentially bound between the two sets of BED intervals.|
|Motif  |Random permutation |Proteins bound to a motif more often than by chance.                |
|Motif  |Motif              |Proteins differentially bound between the two motifs.               |
|Genes  |RefSeq coding genes|Proteins bound to genes more often than other RefSeq genes.         |
|Genes  |Genes              |Proteins differentially bound between the two sets of gene list.    |

### Requirements and acceptable data

#### Reference peak-call data (upper panels of the submission form)

Comprehensive peak-call data as described in **4. Peak browser**. The result will be returned more quickly if the classes of antigens and cell-types are specified.

#### BED (lower panels of the submission form)

[UCSC BED format][UCSC_BED], minimally requiring tab-delimited three columns describing chromosom, starting and ending positions.

```html
chr1<tab>1435385<tab>1436458
chrX<tab>4634643<tab>4635798
```

A header and column 4 or later can be included, but they are ignored for the analysis. BE CAREFUL that the BED files in the following genome assembly are only acceptable:

- hg19 (*H. sapiens*)
- mm9 (*M. musculus*)
- dm3 (*D. melanogaster*)
- ce10 (*C. elegans*)
- sacCer3 (*S. cerevisiae*)

If the BED file is in other genome assembly, convert it to proper assembly with [UCSC liftOver tool][liftOver].

#### Motif (lower panels of the submission form)

A sequence motif described in [IUPAC nucleic acid notation][IUPAC]. In addition to ATGC, ambiguity characters are also acceptable (WSMKRYBDHVN).

#### Gene list (lower panels of the submission form)

Gene symbols described according to following nomenclatures:

* [HGNC][HGNC] (*H. sapiens*)  
* [MGI][MGI] (*M. musculus*)
* [FlyBase][FlyBase] (*D. melanogaster*)
* [WormBase][WormBase] (*C. elegans*)
* [SGD][SGD] (*S. cerevisiae*)

(eg. OCT3/4 => POU5F1; p53 => TP53)

If the gene list are described in other format (eg. Gene IDs in Refseq or Emsemble format), use batch conversion tool such as [DAVID][DAVID] (Convert into OFFICIAL\_GENE\_SYMBOL with Gene ID Conversion Tool).

### Methods

#### 1. Submitted data are converted to BED files depending on the data types.

##### BED

Submitted BED files are just used for further processing. If 'Random permutation' is set for the comparison, the submitted BED intervals are permuted on a random chromosome at a random position for specified times with `bedtools shuffle` command ([bedtools][bedtools]; ver 2.17.0).

##### Motif

Genomic locations perfectly matching to submitted sequence are searched by [Bowtie][bowtie1] (ver 0.12.8) and converted to BED format. If 'Random permutation' is set for the comparison, the BED is used for random permutation as described above.

##### Gene list

Unique TSSs of submitted genes are defined with xxxCanonical.txt.gz* library distributed from [UCSC FTP site][UCSC_FTP].  

\* xxx is a placeholder for:

- "known" (*H. sapiens* and *M. musculus*)
- "flyBase" (*D. melanogaster*)
- "sanger" (*C. elegans*)
- "sgd" (*S. cerevisiae*)

The locations of TSSs are converted to BED format with the addition of widths specified in 'Distance range from TSS' on the submission form. If 'RefSeq coding genes…' is set for the comparison, RefSeq coding genes excluding those in submitted list are processed to BED format as mentioned above.

#### 2.

Counts the overlaps between the BED (originated from 'My data' or 'Compare with') and reference peak-call data (specified on upper panels of the submission form) with `bedtools intersect` command ([BedTools2][bedtools]; ver 2.23.0).

#### 3.

*P*-values are calculated with two-tailed Fisher's exact probability test. The null hypothesis is that the intersection of reference peak-call data with 'My data' occurs in the same proportion to those with 'Compare with'. *Q*-Values are calculated with Benjamini & Hochberg method.

#### 4.

Fold enrichment is calculated by column 6 and 7 of resultant table. If the ratio > 1, the rightmost column is 'TRUE', meaning that the proteins at column 3 binds to 'My data' in a greater proportion than to 'Compare with' features.

<!-- Links to files -->
[dataNumber]: http://devbio.med.kyushu-u.ac.jp/chipatlas/img/DataNumber.png "Data number"
[flowchart]: http://devbio.med.kyushu-u.ac.jp/chipatlas/img/flowchart.png "Flow chart"
[Doc_S1]: http://devbio.med.kyushu-u.ac.jp/chipatlas/docs/Doc_S1.txt
[Doc_S2]: http://devbio.med.kyushu-u.ac.jp/chipatlas/docs/Doc_S2.txt
[Table_S1]: https://docs.google.com/spreadsheets/d/1W-ehO9nZd638sdKIQNw6ENLHsD3Oi5UuxQNLaOAJXIQ/pubhtml

<!-- Links to external web sites -->
[NCBI]: http://www.ncbi.nlm.nih.gov/
[DDBJ]: http://www.ddbj.nig.ac.jp/index-e.html
[ENA]: http://www.ebi.ac.uk/ena
[SRX]: http://www.ncbi.nlm.nih.gov/books/NBK56913/
[NCBImeta]: ftp://ftp.ncbi.nlm.nih.gov/sra/reports/Metadata
[SraToolKit]: http://www.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?view=software
[bowtie2]: http://bowtie-bio.sourceforge.net/bowtie2/index.shtml
[bowtie1]: http://bowtie-bio.sourceforge.net/index.shtml
[samtools]: http://samtools.sourceforge.net
[bedtools]: http://bedtools.readthedocs.org/en/latest/
[UCSCtools]: http://hgdownload.cse.ucsc.edu/admin/exe/
[MACS2]: https://github.com/taoliu/MACS/
[PMID_15702071]: http://www.ncbi.nlm.nih.gov/pubmed/15702071
[HGNC]: http://www.genenames.org
[MGI]: http://www.informatics.jax.org
[FlyBase]: http://flybase.org
[WormBase]: https://www.wormbase.org
[SGD]: http://www.yeastgenome.org
[PMID_25877200]: http://www.ncbi.nlm.nih.gov/pubmed/25877200
[ATCC]: http://www.atcc.org
[MeSH]: http://www.ncbi.nlm.nih.gov/mesh
[UCSC_FTP]: http://hgdownload.cse.ucsc.edu/goldenPath
[STRING]: http://string-db.org
[UCSC_BED]: https://genome.ucsc.edu/FAQ/FAQformat.html#format1
[liftOver]: https://genome.ucsc.edu/cgi-bin/hgLiftOver
[IUPAC]: https://en.wikipedia.org/wiki/Nucleic_acid_notation
[DAVID]: https://david.ncifcrf.gov
