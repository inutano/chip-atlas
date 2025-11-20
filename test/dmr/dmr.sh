#!/bin/bash
curl -X POST \
  -d "antigenClass=dmr" \
  -d "title=test_of_callDMRs" \
  -d "genome=hg38" \
  -d "typeA=srx" \
  --data-urlencode "bedAFile@dataA.srx" \
  -d "descriptionA=CD8" \
  -d "typeB=srx" \
  --data-urlencode "bedBFile@dataB.srx" \
  -d "descriptionB=CD4" \
  -d "format=text" \
  -d "result=www" \
  -d "cellClass=empty" \
  -d "threshold=1" \
  -d "permTime=1" \
  https://dtn1.ddbj.nig.ac.jp:10443/wabi/chipatlas/
