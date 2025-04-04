#!/bin/bash

# Variables for the script
export LC_ALL=C
export PS4='\[\033[36m\]+ $LINENO: \[\033[0m]'
set -eux

# Predefined variables
shufN=1
descriptionA="My data"
descriptionB="Comparison"
title="My data vs Comparison"
hed="Search for common epigenetic features in your data."
srxUrl="http://chip-atlas.org/view?id="

# Positional parameters
bedA="${1}"
bedB="${2}"

typeA="${3}"
typeB="${4}"
descriptionA="${5}"
descriptionB="${6}"
title="${7}"
permTime="${8}"
distanceDown="${9}"
distanceUp="${10}"
genome="${11}"
antigenClass="${12}"
cellClass="${13}"
threshold="${14}"
wabiID="${15}"

# Reference files from arguments
expL="${16}"
fileL="${17}"
id2gene_dir="${18}"
uniqueTSS_dir="${19}"
chromSizes_dir="${20}"
referenceBed_dir="${21}"
btbpToHtml="${22}"

# Input/Output files
EA_TMPDIR="${23}/${wabiID}"
mkdir -p ${EA_TMPDIR}
tmpF="${EA_TMPDIR}/${wabiID}_ea.tmp"

EA_OUTDIR="${24}/${wabiID}"
mkdir -p ${EA_OUTDIR}
outTsv="${EA_OUTDIR}/${wabiID}.result.tsv"
outHtml="${EA_OUTDIR}/${wabiID}.result.html"

touch ${tmpF} ${outTsv} ${outHtml}

# Search and set reference files

# Check if directory exists and the genome is in the directory, exit if not
if [ ! -d "${id2gene_dir}" ]; then
  echo "Error: ${id2gene_dir} does not exist."
  exit 1
else
  id2gene="${id2gene_dir}/id2symbol.${genome}.tsv"
  if [ ! -f "${id2gene}" ]; then
    echo "Error: ${id2gene} does not exist."
    exit 1
  fi
fi

# Check if directory exists and the TSS info is in the directory, exit if not
if [ ! -d "${uniqueTSS_dir}" ]; then
  echo "Error: ${uniqueTSS_dir} does not exist."
  exit 1
else
  uniqueTSSBed="${uniqueTSS_dir}/uniqueTSS.${genome}.bed"
  if [ ! -f "${uniqueTSSBed}" ]; then
    echo "Error: ${uniqueTSSBed} does not exist."
    exit 1
  fi
fi

# Check if directory exists and the chromSizes file is in the directory, exit if not
if [ ! -d "${chromSizes_dir}" ]; then
  echo "Error: ${chromSizes_dir} does not exist."
  exit 1
else
  chromSizes="${chromSizes_dir}/${genome}.chrom.sizes"
  if [ ! -f "${chromSizes}" ]; then
    echo "Error: ${chromSizes} does not exist."
    exit 1
  fi
fi

# Check if directory exists and the dir for the genome is in the directory, exit if not
if [ ! -d "${referenceBed_dir}" ]; then
  echo "Error: ${referenceBed_dir} does not exist."
  exit 1
fi

#
# functions
#

# 入力ファイルが Bed か motif かを判定し、motif ならば Bed に変換する
function motifOrBed() { # $1 = 入力 Bed ファイル名  $2 = Genome
  local inBed=$1
  local genomeForMotifOrBed=$2
  local mb=$(cat $inBed | awk '{
    if ($1 ~ /^chr/) {
      print >> "tmpForMotifOrBed"
      i++
    }
  } END {
    printf "%d", i
  }')
  if [ $mb = "0" ]; then # 入力が motif の場合、Bed に変換
    local motif=$(cat $inBed | sed 's/[^a-zA-Z]//g')
    motifbed $motif $genomeForMotifOrBed >"tmpForMotifOrBed"
  fi
  cat tmpForMotifOrBed | cutBED >$inBed
  rm tmpForMotifOrBed
}

function motifbed() {
  # imported from https://github.com/shinyaoki/chipatlas/blob/master/sh/analTools/wabi/wabi_bin/motifbed
  local query=$1
  local len=`echo $query| wc -c`
  local len=`expr $len - 1`
  if [ ${len} -gt "13" ];then
    local alldna_len=1
  else
    local alldna_len=`expr 14 - $len`
  fi

  local tmpdir="${EA_TMPDIR}/motifbed_temp_"$RANDOM$RANDOM$RANDOM
  mkdir -p $tmpdir

    for sequence in `NtoATGC $query`; do
    echo $sequence >> $tmpdir/$len.motifbed
    if [ `echo $sequence| grep "Error"` ]; then
        echo $sequence    # Error_XL
        rm -r $tmpdir
        exit
    fi
    done

    for LL in `cat $tmpdir/$len.motifbed | tr '\n' ' '`; do
    alldna $alldna_len |\
    awk -v SEQ=$LL '{printf ">" NR $1 "\n" SEQ $1 "\n"}' >> $tmpdir/input_seq
    done

    bowtie -t -a -v0 /home/w3oki/chipatlas/lib/bowtie_index/$2 --suppress 1,5,6,7,8 -f $tmpdir/input_seq |\
    awk -v DIR=$tmpdir -v LEN=$len -v ALLDNA_LEN=$alldna_len '{
    if ($1 == "+") print $2 "\t" $3 "\t" $3+LEN "\t" $1
    else print $2 "\t" $3+ALLDNA_LEN "\t" $3+LEN+ALLDNA_LEN "\t" $1
    }'| sort -k4| awk '!a[$1,$2,$3]++'

    rm -r $tmpdir
}

function NtoATGC() {
  # imported from https://github.com/shinyaoki/chipatlas/blob/master/sh/analTools/wabi/wabi_bin/NtoATGC
  local tmpdir="${EA_TMPDIR}/NtoATGC_tmp"$RANDOM$RANDOM$RANDOM
  mkdir -p $tmpdir

  local len=`echo $1| wc -c`
  local len=`expr $len - 1`

  echo $1 | tr '[a-z]' '[A-Z]' > $tmpdir/0.NtoATGC

  for num in `seq $len`;do
    local prev=`expr $num - 1`
    cat $tmpdir/$prev.NtoATGC |\
    awk -v NUM=$num -v TMPDIR=$tmpdir '{
      enki = substr($1,NUM,1)
      if (enki == "T" || enki == "G" || enki == "C" || enki == "A") {
        print $1 >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "W") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "R") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "M") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "K") {
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "Y") {
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "S") {
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "H") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "B") {
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "V") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "D") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else if (enki == "N") {
        printf("%sA%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sG%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sC%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
        printf("%sT%s\n", substr($1,1,NUM-1), substr($1,NUM+1) ) >> TMPDIR"/"NUM".NtoATGC"
      }
      else {
        print "error" >> TMPDIR"/err.NtoATGC"
      }
    }'
  done 2> $tmpdir/stderr.NtoATGC

  echo aaa >> $tmpdir/err.NtoATGC
  local err=`grep "error" $tmpdir/err.NtoATGC| wc -l`

  if [ ${err} -gt "0" ];then
    NN=`echo $1 | tr '[a-z]' '[A-Z]' |tr -d 'ATGCWRMKYSHBVDN' | wc -c`
    NN=`expr $NN - 1`
    for N in `seq $NN`; do
      echo $1 | tr '[a-z]' '[A-Z]' |tr -d 'ATGCWRMKYSHBVDN'|cut -b $N
    done | sort | uniq | tr -d '\n' | awk '{print "Error_" $1}'
  else
    cat $tmpdir/$len.NtoATGC
  fi

  rm -r $tmpdir
}

function alldna() {
  # imported from https://github.com/shinyaoki/chipatlas/blob/master/sh/analTools/wabi/wabi_bin/alldna
  # merged 4shinsu from https://github.com/shinyaoki/chipatlas/blob/master/sh/analTools/wabi/wabi_bin/4shinsu
  local SeqLen=$1
  local Seq=`echo $((4 ** $SeqLen))`

  local i=0
  while [ $i -lt $Seq ];do
    echo $i
    let i="$i+1"
  done |\
  awk '{
    KETA_MAX=int(log($1)/log(4))
    joyo=$1
    for (keta=KETA_MAX; keta>=0; keta--) {
      printf "%d", joyo/exp(keta*log(4))
      joyo=joyo%exp(keta*log(4))
    }
    printf "\n"
  }' |\
  awk -v SEQLEN=$SeqLen '{printf "%0*d\n", SEQLEN, $1}' |\
  tr 0123 ATGC
}

# 入力ファイルの遺伝子名を Bed に変換する
function geneToBed() { # $1 = 入力 Bed ファイル名  $2 = Genome  $3 = distanceUp  $4 = distanceDown
  local inGene=$1
  local genomeForGeneToBed=$2
  local upBp=$3
  local dnBp=$4
  cat $uniqueTSSBed | awk -v inGene=$inGene -v upBp=$upBp -v dnBp=$dnBp -v id2gene=$id2gene '
  BEGIN {
    while ((getline < id2gene) > 0) {
      gsub(/[^a-zA-Z0-9\t_\n]/, "_", $0)
      G[tolower($1)] = tolower($2)
    }
    while ((getline < inGene) > 0) {
      gsub(/[^a-zA-Z0-9\t_\n]/, "_", $1)
      g[G[tolower($1)]]++
    }
    close(inGene)
  } {
    gene = $4
    gsub(/[^a-zA-Z0-9\t_\n]/, "_", $4)
    if (g[tolower($4)] > 0) {
      beg = ($5 == "+")? $2 - upBp : $3 - dnBp
      end = ($5 == "+")? $2 + dnBp : $3 + upBp
      if (beg < 1) beg = 1
      printf "%s\t%s\t%s\t%s\n", $1, beg, end, gene
    }
  }' | cutBED >tmpForGeneToBed
  mv tmpForGeneToBed $inGene
}

function cutBED() {
  awk -F '\t' -v OFS='\t' '{
    if ($2 < 0) $2 = 0
    if ($3 < 0) $3 = 1
    if ($2 <= $3) print
  }'
}

function qsortBed() {
    # original https://github.com/shinyaoki/chipatlas/blob/master/sh/analTools/wabi/wabi_bin/qsortBed
    local tmpDir="${EA_TMPDIR}/qsortBed_$RANDOM$RANDOM$RANDOM"

    # 作業用ディレクトリ作成
    rm -rf "$tmpDir"
    mkdir -p "$tmpDir" || { echo "Failed to create temporary directory"; return 1; }

    # 入力を染色体ごとに分けてテンポラリファイルに保存
    awk -F '\t' -v tmpDir="$tmpDir/" '{print > (tmpDir $1)}'

    # 各染色体ごとにソートして標準出力に出力
    for chr in $(ls "$tmpDir" | sort -k1,1); do
        sort -k2,2n "$tmpDir/$chr"
    done

    # テンポラリディレクトリのクリーンアップ
    rm -rf "$tmpDir"
}

function qval() {
    # In the original script called like this: /home/w3oki/bin/qval -lL -k6
    local Key=6
    local hn=0
    local tn=1
    local Log=1
    local Exp=1
    local method=BH
    local Rnd=`echo $RANDOM$RANDOM$RANDOM`
    local tmpdir="${EA_TMPDIR}"
    local tmpTxt="$tmpdir/qVal$Rnd.txt"
    local tmpR="$tmpdir/qVal$Rnd.R"

    local pVal=$(cat < /dev/stdin | tee $tmpTxt| cut -f $Key| tail -n +$tn| awk -v Exp=$Exp '{
    if (Exp == 1) print exp($1*log(10))
    else          print
    }'| tr '\n' ','| sed 's/,$//')

cat << DDD > $tmpR
p.value <- c($pVal)
q.values <- p.adjust(p.value, method = "$method")
q.values
DDD

    Rscript $tmpR| awk -v Log=$Log -v tmpTxt=$tmpTxt -v hn=$hn '
    BEGIN {
        while ((getline < tmpTxt) > 0) {
            N++
            str[N] = $0
        }
        for (i=1; i<=hn; i++) print str[i]
        } {
        for (i=2; i<=NF; i++) {
            j++
            if (Log == 0) {
            print str[j+hn] "\t" $i
            } else {
            if ($i == 0) print str[j+hn] "\t" "-324"
            else         print str[j+hn] "\t" log($i) / log(10)
            }
        }
    }'

    rm $tmpTxt $tmpR  # imported from
}

function fisheR() {
  local fishRtmpF="${EA_TMPDIR}/fisheR_$RANDOM$RANDOM$RANDOM"
  cat - > $fishRtmpF
  R --vanilla --args $fishRtmpF << 'DDD' > /dev/null
    args <- commandArgs(trailingOnly = T)
    d <- read.table(args[1], sep="\t", head=F)
    k <- as.numeric("2")

    t <- d[,k:(k+3)]
    f <- c(1:nrow(t))

    for (i in 1:nrow(t)) {
      tbl <- matrix(as.numeric(t[i,]), ncol=2, byrow=T)
      f[i] <- fisher.test(tbl)[1]
    }
    out <- cbind(d, as.numeric(f))

    outtsv <- paste(args[1], ".tmp___Rfisher", sep="")
    write.table(out, quote = FALSE, sep = "\t", file=outtsv, append = FALSE, col.names=F, row.names=F)
DDD
  cat $fishRtmpF.tmp___Rfisher
  rm $fishRtmpF.tmp___Rfisher
  rm $fishRtmpF
}

#
# main
#

# タイプごとに入力ファイルを処理
case $typeA in
"bed") # TypeA = BED の場合、モチーフは BED に、BED はそのまま。
  motifOrBed $bedA $genome
  case $typeB in
  "rnd") # TypeB = random の場合、bedtools shuffle を行う
    for i in $(seq $permTime); do
      shuffleBed -i $bedA -g $chromSizes
    done >$bedB
    shufN=$permTime
    ;;
  "bed") # TypeB = BED の場合、モチーフは BED に、BED はそのまま。
    motifOrBed $bedB $genome
    ;;
  esac
  ;;
"gene") # TypeA = gene の場合、geneA を BED に変換
  geneToBed $bedA $genome $distanceUp $distanceDown
  case $typeB in
  "refseq") # TypeB = RefSeq の場合、geneA 以外の遺伝子を BED に変換
    cat "$uniqueTSSBed" | awk -v bedA=$bedA '
        BEGIN {
          while ((getline < bedA) > 0) g[$4]++
        } {
          if (g[$4] + 0 < 1) print $4
        }' >$bedB
    geneToBed $bedB $genome $distanceUp $distanceDown
    ;;
  "userlist") # TypeB = userGenes の場合、そのまま BED に変換
    geneToBed $bedB $genome $distanceUp $distanceDown
    ;;
  esac
  ;;
esac

# 入力bedファイルのチェック
wclA=$(cat $bedA | wc -l)
wclB=$(cat $bedB | wc -l)
wclAB=$(echo $wclA $wclA | awk '{printf $1 * $2}')
if [ $wclAB = "0" ]; then
  echo "Input data is empty or bad." | tee "$outTsv".tmp >"$outHtml".tmp
  exit
fi

# ライブラリファイルの選択
bedL=$(cat $fileL | awk -F '\t' -v referenceBed_dir="$referenceBed_dir" -v genome="$genome" -v antigenClass="$antigenClass" -v cellClass="$cellClass" -v threshold="$threshold" '{
  if (antigenClass == "Bisulfite-Seq") {
    th = "bs"
  } else {
    th = (threshold + 0) / 10
  }
  if ($2 == genome && $3 == antigenClass && $5 == cellClass && $4$6 == "--" && $7 == th) {
    printf referenceBed_dir "/%s/public/%s.bed", genome, $1
  }
}') # chipatlas/results/mm9/public/ALL.ALL.05.AllAg.AllCell.bed
echo $bedL

# 入力 Bed ファイルをソート
{
  cut -f1-3 $bedA | awk -F '\t' '{print $0 "\tA"}'
  cut -f1-3 $bedB | awk -F '\t' '{print $0 "\tB"}'
} | tr -d '\015' | awk '{print $0 "\t" NR}' | qsortBed >$tmpF

# bedtools2
for bedL in $(ls $bedL.*); do
  awk '{x[$4]++} END {for (i in x) print i "\t" x[i]}' $bedL >>"$tmpF"3
  bedtools intersect -sorted -a $bedL -b $tmpF -wb >>"$tmpF"2
done

cat "$tmpF"2 | awk -F '\t' -v wclA=$wclA -v wclB=$wclB -v shufN=$shufN '{  # カウント
  if(NR % 1000000 == 0) delete x
  if (!x[$4,$9]++) {
    if ($8 == "A") a[$4]++
    else           b[$4]++
  }
  SRX[$4]++
} END {
  for (srx in SRX) {
    n1 = a[srx]
    n2 = wclA - a[srx]
    n3 = int(b[srx]/shufN + 0.5)
    n4 = wclB/shufN - int(b[srx]/shufN + 0.5)

    if (n2 < 0) {
      n1 = wclA
      n2 = 0
    }

    if (n4 < 0) {
      n3 = wclB/shufN
      n4 = 0
    }

    printf "%s\t%d\t%d\t%d\t%d\n", srx, n1, n2, n3, n4
  }
}' | awk -F"\t" -v OFS="\t" '$2>=0 && $3>=0 && $4>=0 && $5>=0' | fisheR | awk -F '\t' '{    # Fisher 検定
  for (i=1; i<NF; i++) printf "%s\t", $i
  if ($NF == 0) print "-324"
  else          print log($NF)/log(10)
}' | sort -k6n | qval | awk -F '\t' -v expL=$expL '  # Fold enrichment の計算
BEGIN {
  N = split(",.hypermr,.hmr,.pmd", n, ",")
  while((getline < expL) > 0) {
    for (i=1; i<=N; i++) a[$1 n[i]] = $3 "\t" $4 "\t" $5 "\t" $6
  }
} {
  if (($2+$3)*$4 == 0) FE = "inf"
  else                 FE = ($2/($2+$3))/($4/($4+$5))  # Fold enrichment = (a/ac)/(b/bd)
  printf "%s\t%s\t%s/%s\t%s/%s\t%s\t%s\t%s\n", $1, a[$1], $2, $2+$3, $4, $4+$5, $6, $7, FE
}' | sort -t $'\t' -k8n -k10nr | awk -F '\t' -v tmp="$tmpF"3 '  # 総ピーク数
BEGIN {
  while ((getline < tmp) > 0) peakN[$1] += $2
} {
  if ($2$4 !~ "No description" && $2$4 !~ "Unclassified") {
    srx = $1
    if ($2 == "DNase-seq" || $2 == "ATAC-Seq") $3 = "Accessible chromatin"
    if ($2 == "Bisulfite-Seq") {
      split($1, s, ".")
      $1 = s[1]
      $3 = s[2]
      sub("hypermr", "Hyper MR", $3)
      sub("hmr", "Hypo MR", $3)
      sub("pmd", "Partial MR", $3)
    }
    for (i=1; i<=5; i++) printf "%s\t", $i
    printf "%d\t", peakN[srx]
    for (i=6; i<=NF; i++) printf "%s\t", $i
    printf "\n"
  }
}' | cut -f1-11 | tee $outTsv.tmp | awk -F '\t' -v btbpToHtml="${btbpToHtml}" -v descriptionA="$descriptionA" -v descriptionB="$descriptionB" -v hed="$hed" -v title="$title" -v wabiID="$wabiID" -v srxUrl=$srxUrl '  # html に変換
BEGIN {
  while ((getline < btbpToHtml) > 0) {
    gsub("___Title___", title, $0)
    gsub("___Targets___", descriptionA, $0)
    gsub("___References___", descriptionB, $0)
    gsub("___Header___", hed, $0)
    gsub("___Caption___", title, $0)
    gsub("___WABIid___", wabiID, $0)
    print
  }
} {
  print "<tr>"
  print "<td title=\"Open this Info...\"><a target=\"_blank\" style=\"text-decoration: none\" href=\"" srxUrl $1 "\">" $1 "</a></td>"
  for (i=2; i<=5; i++) print "<td>" $i "</td>"
  for (i=6; i<=8; i++) printf "<td align=\"right\">%s</td>\n", $i
  for (i=9; i<=10; i++) printf "<td align=\"right\">%.1f</td>\n", $i
  printf "<td align=\"right\">%s</td>\n", ($11 == "inf")? 99999 : sprintf("%.2f", $11)
  printf "<td>%s</td>\n", ($11 > 1 || $11 == "inf")? "TRUE" : "FALSE"
  print "</tr>"
} END {
  print "</tbody>"
  print "</table>"
}' | awk -v ac="$antigenClass" '{
  if (ac ~ "ATAC" || ac ~ "DNase" || ac ~ "Bisulfite") {
    if ($0 ~ "th title") {
      gsub("Antigen class", "Experiment type", $0)
      gsub("Antigen", "Feature", $0)
    }
  }
  print
}' >$outHtml.tmp

mv $outTsv.tmp $outTsv
mv $outHtml.tmp $outHtml

rm $tmpF "$tmpF"2 "$tmpF"3 $bedA $bedB
