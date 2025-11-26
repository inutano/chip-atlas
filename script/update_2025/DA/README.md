# Description of the Downloaded Files

- **`wabi_result.igv.xml`** (IGV Session File)
  This file allows visualization of DPRs or DMRs alongside the original data within IGV (Integrative Genomics Viewer).
  - **Important:** This file **must be placed in the same directory as the `wabi_result.igv.bed` file**, otherwise the DPR or DMR track will not be properly loaded.

- **`wabi_result.log`** (Analysis Log)
  A log file documenting the analysis process used to identify DPRs or DMRs.
  - Contains metadata such as the `WABI_ID`, which is necessary for troubleshooting.

- **`wabi_result.bed`** (BED File for Analysis)
  Contains the detected DPRs or DMRs in standard BED format, suitable for downstream computational analysis.
  - This file can be directly imported into various bioinformatics tools for further investigation.

- **`wabi_result.igv.bed`** (BED File for IGV Visualization)
  Contains the detected DPRs or DMRs in BED format optimized for browsing within IGV.
  - To properly visualize the tracks in IGV, ensure this file is located in the same directory as the `wabi_result.igv.xml` file.


# Contact

- **Shinya Oki** (Kumamoto University)
  - **Email:** [okishinya@kumamoto-u.ac.jp](mailto:okishinya@kumamoto-u.ac.jp?cc:zou@kumamoto-u.ac.jp)
  - **Troubleshooting:** Please provide the `WABI_ID` indicated in the `wabi_result.log` file when requesting support.