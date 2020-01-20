#!/bin/sh
set -eux
genome_references=(
  "hg19\tGRCh37"
  "mm9\tmm9"
  "rn6\trn6"
  "dm3\tdm3"
  "ce10\tce10"
  "sacCer3\tsacCer3"
)
threshold=(
  "05"
  "10"
  "20"
  "50"
)
for genome in ${genome_references[@]}; do
  for th in ${threshold[@]}; do
    sp=$(echo -e "${genome}" | cut -f 1)

    genome_version=$(echo -e "${genome}" | cut -f 2)
    data_version=$(date "+%Y%m%d-%H%M")
    ttl_fname="chip-atlas.${genome_version}.${data_version}.${th}.ttl"

    url_base="http://dbarchive.biosciencedbc.jp/kyushu-u/${sp}/allPeaks_light"
    fname="allPeaks_light.${sp}.${th}.bed.gz"

    wget "${url_base}/${fname}"
    gunzip -c "${fname}" |\
     ./bed2ttl \
       -v data_version=${data_version} \
       -v genome_version=${genome_version} \
       > ${ttl_fname}
  done
done
