#!/bin/sh
set -eux
mkdir -p "./data/bed"
mkdir -p "./data/ttl"
genome_references=(
  "hg19"
  "mm9"
  "rn6"
  "dm3"
  "ce10"
  "sacCer3"
)
threshold=(
  "05"
  "10"
  "20"
  "50"
)
for genome in ${genome_references[@]}; do
  for th in ${threshold[@]}; do
    data_version=$(date "+%Y%m%d-%H%M")
    ttl_fname="ChIPAtlas-TFBS-${data_version}.${genome}.${th}.ttl"

    url_base="http://dbarchive.biosciencedbc.jp/kyushu-u/${genome}/allPeaks_light"
    fname="allPeaks_light.${genome}.${th}.bed.gz"

    wget -nc -P "./data/bed" "${url_base}/${fname}"
    gunzip -c "./data/bed/${fname}" |\
      gawk -f ./bin/chr2genbank -v ref=$(pwd -P)/reference -v genome_version=${genome} |\
      gawk -f ./bin/bed2ttl -v data_version=${data_version} \
      > "./data/ttl/${ttl_fname}"
  done
done
