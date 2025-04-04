#!/bin/bash

# bedA="${1}"
# bedB="${2}"
# typeA="${3}"
# typeB="${4}"
# descriptionA="${5}"
# descriptionB="${6}"
# title="${7}"
# permTime="${8}"
# distanceDown="${9}"
# distanceUp="${10}"
# genome="${11}"
# antigenClass="${12}"
# cellClass="${13}"
# threshold="${14}"
# job_id="${15}"

mkdir -p results/mm9/public

. ./enrichment-analysis.sh \
"./geneList_A.txt" \
"./geneList_B.txt" \
"gene" \
"userlist" \
"dataset A" \
"dataset B" \
"My project" \
1 \
5000 \
5000 \
"mm9" \
"TFs and others" \
"Bone" \
50 \
"jobid-hogehoge" \
"./reference/experimentList.tab" \
"./reference/fileList.tab" \
"./reference" \
"./reference" \
"./reference" \
"./reference/btbpToHtml.txt" \
"./tmp"
