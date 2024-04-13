#!/bin/bash
#$ -S /bin/bash
#$ -cwd

SRX_LST=("to_be_assigned" "to_be_assigned")   # SRX list (comma-separated)
GENOME="to_be_assigned"       # GENOME
OUTDIR="."
PROJECT_NAME="diffbind_$(date +%s)_$RANDOM$RANDOM$RANDOM"
GROUP_LBL=("g1" "g2")
GROUP_LBL_USER=("g1" "g2")
BedTHRES=05

while getopts ":1:2:o:p:g:t:a:b:i:h" option
do
  case "$option" in
    h)
      echo -e "

Usage:
  diffbind -1 <SRX_list (comma-separated)> -2 <SRX_list (comma-separated)> -g <genome> [-o <outdir>] [-p <outfile_name>] [-a <group_name_of_SRXs1>] [-b <group_name_of_SRXs2>] [-t <threshold_of_peaks>]

Example:
  diffbind -1 SRX10109394,SRX10109395 -2 SRX1592791,SRX1592792,SRX1592793 -a ips -b fb -g hg38 -o /home/zou/diffbind/test -p diffbind_H3K37ac_ips_vs_fb

Options:
  -1 & -2) SRXs of ChIP/ATAC/DNase (comma-separated)
  -g)      Genome assembly
  -o)      output dir
  -p)      filename
  -a)      label for -1
  -b)      label for -2
  -t)      MACS2 score threshold
  -i)      wabi id
"
    exit 0
    ;;

    1) SRX_LST[0]="$OPTARG";;    
    2) SRX_LST[1]="$OPTARG";;
    g) GENOME="$OPTARG";;      
    o) OUTDIR="$OPTARG";;
    p) PROJECT_NAME="$OPTARG";; 
    a) GROUP_LBL_USER[0]="$OPTARG";;
    b) GROUP_LBL_USER[1]="$OPTARG";;
    t) BedTHRES="$OPTARG";;
    i) WABIID="$OPTARG"
  esac
done

shift $(expr $OPTIND - 1)

# Functions
define_variables() {
  ChIPDIR=/home/okishinya/chipatlas
  BIGWIG_DIR=$ChIPDIR/results/$GENOME/BigWig 
  BedTHRES=$(echo $BedTHRES| awk '{printf "%02d", $1}')
  BED_DIR=$ChIPDIR/results/$GENOME/Bed$BedTHRES/Bed 
  RUNINFO=$ChIPDIR/lib/metadata/SRA_Metadata_RunInfo.tab  # srx  layout  srr
  EXPERIMENT_LIST=$ChIPDIR/lib/assembled_list/experimentList.tab
  READS_BASE=$ChIPDIR/lib/metadata/SRX_reads_bases.tab

  [ "$USER" == "w3oki" ] && PREFIX=$OUTDIR/$WABIID || PREFIX=$OUTDIR/$PROJECT_NAME
  # PREFIX=$PROJECT_NAME
  [ $PREFIX != "" ] && rm -f $PREFIX.*

  mkdir -p $PREFIX.tmp
  LOGFILE=$PREFIX.log
  : > $LOGFILE

  SRX_COUNT=($(echo ${SRX_LST[0]}| awk -F"," '{print NF}') $(echo ${SRX_LST[1]}| awk -F"," '{print NF}'))
}

add_parameters_to_log() {
  Start_jst=$(date "+%Y-%m-%dT%H:%M:%S+0900 (JST)")
  Start_utc=$(date --utc "+%Y-%m-%dT%H:%M:%SZ (UTC)")
  echo "

========= Parameters ========" >> $LOGFILE
  cat user_request.json >> $LOGFILE
  echo "" >> $LOGFILE
  echo "" >> $LOGFILE
}

load_urls() {
  URLMETA=$PREFIX.tmp/urlnreads.tsv
  : > $URLMETA
  for i in 0 1; do
    echo ${SRX_LST[$i]}| tr ' ' ','| awk -F"," -v OFS="," -v i=$i -v PREFIX="$PREFIX" '{
      nread = PREFIX".tmp/urlnreads.tsv"
      for (j=1; j<=NF; j++) {
        if ($j ~ /^http.+$/) {
          urlcount++
          outname = PREFIX".tmp/url"i"_"urlcount
          bw = outname".bw"
          bed = outname".bed"
          split($j, x, "___URLSEP___")
          print "wget -q -O "bw" \""x[1]"\""
          print "wget -q -O "bed" \""x[2]"\""
          print "/usr/bin/echo -e \"url"i"_"urlcount"\t"x[1]"\t"x[2]"\t"x[3]"\" >> "nread
        }
      }
    }'| sh

    SRX_LST[$i]=$(
      echo ${SRX_LST[$i]}| tr ' ' ','| awk -F"," -v OFS="," -v i=$i '{
        for (j=1; j<=NF; j++) {
          if ($j ~ /^http.+$/) {
            urlcount++
            $j = "url"i"_"urlcount
          }
        }
        print $0
      }'
    )
  done
}

init_log() {
  echo "===== Diff Analysis =====
request ID = $WABIID

Genome = $GENOME

Queried SRXs
  ${GROUP_LBL_USER[0]}: ${SRX_LST[0]}
  ${GROUP_LBL_USER[1]}: ${SRX_LST[1]}

" >> $LOGFILE
}

check_srx_and_genome_is_not_empty() {
  echo "Checking parameters ... " >> $LOGFILE
  echo "" >> $LOGFILE
  if [ ${SRX_LST[0]} == "to_be_assigned" -o ${SRX_LST[0]} == "to_be_assigned" ]; then
    echo '  ![ERROR] Experiments are not properly assigned.' >> $LOGFILE
  elif [ ${SRX_COUNT[0]} -lt 1 -o ${SRX_COUNT[1]} -lt 1 ]; then
    echo '  ![ERROR] At least one experiment ID for each group should be assigned.' >> $LOGFILE
  elif [ $GENOME == "to_be_assigned" ]; then
    echo '  ![ERROR] Genome assembly cannot be empty.' >> $LOGFILE
  elif [ ${SRX_COUNT[0]} -eq 1 -o ${SRX_COUNT[1]} -eq 1 ]; then
    echo '  ![WARNING] Detection of diffpeak regions without replicate is not recommended.' >> $LOGFILE
  fi
}

count_error() {
  ERROR_COUNT=$(grep -cF '![ERROR]' $LOGFILE)
  if [ $ERROR_COUNT -gt 0 ]; then
    echo "!! Abnormal termination !! Please check the parameters or contact the administers." >> $LOGFILE
    kill ${PIDs[@]}
    exit 1
  fi
}

get_gsm2srx() {  # gsm -> srx
  count_error
  for i in 0 1; do
    echo ${SRX_LST[$i]}| tr ' ' ','| awk -F"	" -v OFS="	" -v GENOME="$GENOME" '{
      c = split($1, id, ",")
      for (i=1; i<=c ;i++) {
        if (id[i] ~ /^GSM[0-9]+$/) gsm_count++
      }
      if (gsm_count > 0) {
        while ("cat /home/okishinya/chipatlas/lib/assembled_list/experimentList.tab| grep "GENOME| getline) {
          if ($9 ~ /^GSM[0-9]{4,}: .*/) {
            split($9, x, ":")
            srx[x[1]] = $1
          }
        }
      }
      for (i=1; i<=c ;i++) {
        if      (id[i] ~ /^[SED]RX[0-9]+$/) print id[i], id[i]
        else if (id[i] ~ /^GSM[0-9]+$/ && length(srx[id[i]]) > 0)     print id[i], srx[id[i]]
      }
    }'
  done > $PREFIX.tmp/gsm2srx.tab
  GSM2SRX=$PREFIX.tmp/gsm2srx.tab
}

check_srx_genome_pair_is_correct() {
  count_error

  echo "Checking match of experiments and genome ... " >> $LOGFILE
  echo "" >> $LOGFILE

  cat $EXPERIMENT_LIST| \
  awk -F"	" -v SRX_LST=$(echo ${SRX_LST[@]}| tr ' ' ',') \
  -v GENOME="$GENOME" -v GSM2SRX="$GSM2SRX" -v URLMETA="$URLMETA" '
  BEGIN {
    while (getline < URLMETA) {
      bw[$1] = $2
      bed[$1] = $3
      nread[$1] = $4
    }
    while (getline < GSM2SRX) {
      s[$1] = $2
      g[$2] = $1
    }
    c = split(SRX_LST, tmp, ",")
    for (i=1; i<=c; i++) id[tmp[i]]++
    organism["hg38"] = organism["hg19"] = "H. sapiens (hg38, hg19)"
    organism["mm10"] = organism["mm9"]  = "M. musculus (mm10, mm9)"
    organism["rn6"]                     = "R. norvegicus (rn6)"
    organism["dm6"]  = organism["dm3"]  = "D. melanogaster (dm6, dm3)"
    organism["ce11"] = organism["ce10"] = "C. elegans (ce11, ce10)"
    organism["sacCer3"]                 = "S. cerevisiae (sacCer3)"
    err_count = 0
  } g[$1] in id {
    genome[$1] = $2
    antclass[$1] = "\""$3"\","
    antigen[$1] = "\""$4"\","
    celltypecls[$1] = "\""$5"\","
    celltype[$1] = "\""$6"\","
    celldesc[$1] = "\""$7"\","
    title[$1] = "\""$9"\","
    for (i=10; i<=NF; i++) meta[$1] = meta[$1]" "$i","
  } END {
    for (k=1; k<=c; k++) {
      i = tmp[k]
      if (i ~ /^url.+$/) {
        print "  \""i"\": {"
        print "    \"bigWig\": \""bw[i]"\","
        print "    \"Peak\": "bed[i]","
        print "    \"# of reads\": "nread[i]
        print "  }"
        print ""
      } else if (organism[genome[s[i]]] != organism[GENOME]) {
        err_count++
        print "  ![ERROR] "i": The organism should be "organism[genome[s[i]]]"."
      } else if (err_count == 0) {
        sub(" ", "", meta[s[i]])
        meta[s[i]] = "\""meta[s[i]]"\""
        gsub(";\"", "\"", meta[s[i]])
        print "  \""g[s[i]]"\": {"
        if (s[i] != g[s[i]]) print "    \"SRX\": \""s[i]"\","
        print "    \"Antigen class\": "antclass[s[i]]
        print "    \"Antigen\": "antigen[s[i]]
        print "    \"Cell type class\": "celltypecls[s[i]]
        print "    \"Cell type\": "celltype[s[i]]
        print "    \"Title\": "title[s[i]]
        print "    \"Metadata by authors\": "meta[s[i]]
        print "  }"
        print ""
      }
    }
  }' >> $LOGFILE
}

do_gsm2srx() {
  count_error
  for i in 0 1; do
    SRX_LST[$i]=$(
      echo ${SRX_LST[$i]}| tr ' ' ','| awk -F"	" -v GSM2SRX="$GSM2SRX" '
      BEGIN {
        while (getline < GSM2SRX) srx[$1] = $2
      } {
        c = split($1, x, ",")
        for (i=1; i<=c; i++) {
          (x[i] in srx) ? out = out","srx[x[i]] : out = out","x[i]
        }
        sub(",", "", out)
        print out
      }'
    )
  done
}

def_var2() {
  count_error
  eval $(echo ${GROUP_LBL[@]}| awk -v SRX_COUNT=$(echo ${SRX_COUNT[@]}| tr ' ' ',') \
    -v SRX_LST=$(echo ${SRX_LST[@]}| tr ' ' ',') -v BED_DIR="$BED_DIR" \
    -v BedTHRES="$BedTHRES" -v PREFIX="$PREFIX" '
  BEGIN {
    split(SRX_COUNT, count, ",")
    c = split(SRX_LST, srx, ",")
  } {
    for (i=1; i<=2; i++) {
      for (j=1; j<=count[i]; j++) {
        names = names" "$i""j
        grps = grps" "$i
      }
    }

    for (i=1; i<=c; i++) {
      (srx[i] ~ /^url.+$/) ? files = files" "PREFIX".tmp/"srx[i]".bed" : files = files" "BED_DIR"/"srx[i]"."BedTHRES".bed"
    }

    sub(" ", "", names)
    sub(" ", "", grps)
    sub(" ", "", files)
    print "grps=\""grps"\""
    print "names=\""names"\""
    print "files=\""files"\""
  }')
}

check_bw_exist() {
  count_error

  echo "Checking presence of queried experiments ... " >> $LOGFILE
  echo "" >> $LOGFILE

  for srx in $(echo ${SRX_LST[@]}| tr ',' ' '); do
    if [[ $srx =~ ^url.+$ ]]; then
      if   [ ! -e $PREFIX.tmp/$srx.bw ]; then
        echo '  ![ERROR] '$srx': bigWig files were not correctly loaded.' >> $LOGFILE
      elif [ ! -e $PREFIX.tmp/$srx.bed ]; then
        echo '  ![ERROR] '$srx': Peak files were not correctly loaded' >> $LOGFILE
      fi
    else
      if [ ! -e $BIGWIG_DIR/$srx.bw ]; then
        echo ' ![ERROR] '$srx: $BIGWIG_DIR/$srx'.bw is not included in ChIP-Atlas.' >> $LOGFILE
      elif [ ! -e $BED_DIR/$srx.$BedTHRES.bed ]; then
        echo '  ![ERROR] '$srx: $BED_DIR/$srx.$BedTHRES'.bed is not included in ChIP-Atlas.' >> $LOGFILE
      fi
    fi
  done
}

get_peak_list() {
  count_error

  echo "Peak multiinter ... " >> $LOGFILE
  echo "" >> $LOGFILE

  bedtools multiinter -names $names -i $files| awk -F"	" -v OFS="	" '{
    $4 = "peak_"NR
    print
  }'| cut -f1-4 > $PREFIX.tmp/peak_list.bed
}

get_meta() {
  count_error
  echo ${SRX_LST[@]}| tr ' ' ','| \
  awk -F"," -v OFS="	" -v names=$(echo "$names"| tr ' ' ',') -v grps=$(echo "$grps"| tr ' ' ',') \
    -v genome="$GENOME" -v cmd1="cat $RUNINFO" -v cmd2="cat $EXPERIMENT_LIST" -v cmd3="cat $READS_BASE" '
  BEGIN {
    c = split(names, grp, ",")
    split(grps, tag, ",")
  } {
    for (i=1; i<=c; i++) {
      lbl[$i] = grp[i]
      g[$i] = tag[i]
      print $i, lbl[$i], g[$i]
    }
  }' > $PREFIX.tmp/labels.tab
  LABELS=$PREFIX.tmp/labels.tab

  srxs=$(echo ${SRX_LST[@]}| tr ' ' ',')
  cat $RUNINFO| awk -F"	" -v OFS="	" -v srxs="$srxs" '
  BEGIN {
    c = split(srxs, x, ",")
    for (i=1; i<=c; i++) srx_lst[x[i]]++
  } $1 in srx_lst {
    print $1, $2
  }' > $PREFIX.tmp/SRA_Metadata_RunInfo.tab
  RUNINFO=$PREFIX.tmp/SRA_Metadata_RunInfo.tab

  cat $EXPERIMENT_LIST| awk -F"	" -v OFS="	" -v srxs="$srxs" -v genome="$GENOME" '
  BEGIN {
    c = split(srxs, x, ",")
    for (i=1; i<=c; i++) srx_lst[x[i]]++
  } ($1 in srx_lst) && ($2 == genome) {
    split($8, col, ",")
    print $1, col[1], col[2], col[3]
  }' > $PREFIX.tmp/experimentlist.tab
  EXPERIMENT_LIST=$PREFIX.tmp/experimentlist.tab

  cat $READS_BASE| awk -F"	" -v OFS="	" -v srxs="$srxs" '
  BEGIN {
    c = split(srxs, x, ",")
    for (i=1; i<=c; i++) srx_lst[x[i]]++
  } $1 in srx_lst {
    print $1, $3
  }' > $PREFIX.tmp/SRX_reads_bases.tab
  READS_BASE=$PREFIX.tmp/SRX_reads_bases.tab
}

bw_to_bg() {
  count_error
  srx="$1"
  if [[ $srx =~ ^url.+$ ]]; then
    bw=$PREFIX.tmp/$srx.bw
  else
    bw=$BIGWIG_DIR/$srx.bw
  fi
  bg=$PREFIX.tmp/$srx.bg
  bigWigToBedGraph $bw $bg
}

bed_inter() {
  count_error
  bedtools intersect -a $PREFIX.tmp/$srx.bg -b $PREFIX.tmp/peak_list.bed -sorted -wa -wb| cut -f2-4,8| \
  awk -F"	" -v OFS="	" -v srx="$srx" -v cmd1="cat $LABELS" -v cmd2="cat $EXPERIMENT_LIST" \
      -v cmd3="cat $READS_BASE" -v cmd4="cat $URLMETA" '
  BEGIN {
    while (cmd1| getline) name[$1]   = $2
    while (cmd2| getline) nreads[$1] = $2
    while (cmd3| getline) nbase[$1]  = $2
    while (cmd4| getline) nreads[$1] = $4
    readlen = nbase[srx] / nreads[srx]
  } {
    sum[$4] += ($2 - $1) * $3
  } END {
    for (i in sum) print i, name[srx], int(sum[i]/readlen + 1)
  }' > $PREFIX.tmp/$srx.count.tsv
}

bg_to_count() {
  count_error
  bg="$1"
  if [[ $srx =~ ^url.+$ ]]; then
    cat $bg| awk -F"	" -v OFS="	" -v srx="$srx" -v READS_BASE="$READS_BASE" '{
      if ($4 != int($4)) exit 1
      else               nbase += $4 * ($3 - $2)
    } END {
      if (nbase != "") print srx, nbase >> READS_BASE
    }'
    [ $? -eq 1 ] && echo '  ![ERROR] '$srx': the coverage should be given in integer format' >> $LOGFILE || bed_inter
  else
    cat $bg| awk -F"	" -v OFS="	" -v srx="$srx" -v cmd1="cat $RUNINFO" -v cmd2="cat $EXPERIMENT_LIST" '
    BEGIN {
      while (cmd1| getline) layout[$1] = $2
      while (cmd2| getline) {
        nreads[$1]  = $2
        ratemap[$1] = $3
        ratedup[$1] = $4
      }
    } {
      read = int($4 * nreads[srx] * ratemap[srx]/100 * (100-ratedup[srx])/100 / 1000000 * (layout[srx]+1) + 1)
      print $1, $2, $3, read
    }'| bedtools intersect -a stdin -b $PREFIX.tmp/peak_list.bed -sorted -wa -wb| cut -f2-4,8| \
    awk -F"	" -v OFS="	" -v srx="$srx" -v cmd1="cat $LABELS" -v cmd2="cat $EXPERIMENT_LIST" \
        -v cmd3="cat $READS_BASE" -v cmd4="cat $URLMETA" -v cmd5="cat $RUNINFO| grep $srx"  '
    BEGIN {
      while (cmd1| getline) name[$1]   = $2
      while (cmd2| getline) nreads[$1] = $2
      while (cmd3| getline) nbase[$1]  = $2
      while (cmd4| getline) nreads[$1] = $4
      while (cmd5| getline) layout[$1] = $2
      readlen = (nbase[srx] / nreads[srx]) / (layout[srx] + 1)
    } {
      sum[$4] += ($2 - $1) * $3
    } END {
      for (i in sum) print i, name[srx], int(sum[i]/readlen + 1)
    }' > $PREFIX.tmp/$srx.count.tsv
  fi
}

bw_to_count() {
  srx_lst="$1"
  for srx in $(echo $srx_lst| tr ',' ' '); do
    count_error
    bw_to_bg $srx
    bg_to_count $PREFIX.tmp/$srx.bg
  done
}

get_count_list() {
  count_error
  eval $(echo ${SRX_LST[@]}| tr ' ' ','| awk -F"," -v DIR="$PREFIX.tmp" '{
    for (i=1; i<=NF; i++) files = files" "DIR"/"$i".count.tsv"
    sub(" ", "", files)
    print "files=\""files"\""
  }')
}

combine_count_tbl() {
  count_error
  cat $files| awk -v OFS="	" -v header="$(echo $names| tr ' ' ',')" '{
    r[$1]++
    v[$1"__SEP__"$2] = $3
  } END {
    c = split(header, h, ",")
    for (i=1; i<=c; i++) outH = outH"	"h[i]
    print outH
    for (R in r) {
      out = ""
      for (i=1; i<=c; i++) {
        V = v[R"__SEP__"h[i]]
        if (V=="") V = "0"
        out = out"	"V
      }
      print R""out
    }
  }' > $PREFIX.tmp/count.tsv
}

getDegs() {
  echo "Running edgeR ... " >> $LOGFILE
  echo "" >> $LOGFILE

  count_error
  count_path="$1"
  lbls_path="$2"
  peakbed_path="$3"
  prefix="$4"

  /home/okishinya/zou/miniconda3/envs/r420/bin/R --vanilla --args "$count_path" "$lbls_path" "$peakbed_path" "$prefix" << 'EOF' > /dev/null
    args <- commandArgs(trailingOnly = T)
    count_path   <- as.character(args[1])
    lbls_path    <- as.character(args[2])
    peakbed_path <- as.character(args[3])
    prefix       <- as.character(args[4])

    library(edgeR)

    count <- read.table(count_path, sep="	", header=T, row.names=1)
    factor <- read.table(lbls_path, sep="	", header=F)$V3
    peakbed <- read.table(peakbed_path, sep="	", header=F, row.names=4)[, 1:3]

    count <- as.matrix(count)

    group <- factor(factor)
    d <- DGEList(counts = count, group = group)

    keep <- filterByExpr(d, group=group)
    #低発現遺伝子をフィルタリング
    d <- d[keep, , keep.lib.sizes=FALSE]
    d <- calcNormFactors(d)    #TMM正規化

    if (is.na(estimateCommonDisp(d)$common.dispersion)) { # replicate なしの場合 (n1 vs n1)
      d <- estimateGLMCommonDisp(d, method="deviance", robust=T, subset=NULL)    #モデル構築(common Dispersionを算出)
    } else {                                                       # replicate ありの場合 (n3 vs n3   or   n1 vs n3)
      d <- estimateCommonDisp(d)  #全遺伝子commonの分散を計算 （リンク）
      d <- estimateTagwiseDisp(d) #moderated tagwise dispersionの計算 （リンク）
    }

    result <- exactTest(d)       #exact test（リンク）
    res <- as.data.frame(topTags(result, n=nrow(count)))[, c(1, 3, 4)]

    if (is.null(d$pseudo.counts)) {
      norm_count <- cpm(d, normalized.lib.sizes=T)
    } else {
      norm_count <- d$pseudo.counts
    }

    norm_count <- formatC(norm_count, digits=2, format="f")

    group <- data.frame(con=factor(factor))

    log2fc <- formatC(res$logFC, digits=2, format="f")
    pval <- formatC(log(res$PValue, 10), digits=1, format="f")
    padj <- formatC(log(res$FDR, 10), digits=1, format="f")

    res_row <- row.names(res)
    res <- cbind(log2fc, pval, padj)
    row.names(res) <- res_row

    names(factor) <- colnames(norm_count)
    tags <- unique(factor)

    combine_row <- function(row) {
      res <- paste(row, collapse=",")
      return(res)
    }

    tbl2grp <- function(grp) {
      norm_count <- norm_count[, which(factor==tags[grp])]
      if (is.vector(norm_count)) {
        res <- norm_count
      } else {
        res <- apply(norm_count, 1, combine_row)
      }
      return(res)
    }

    norm_count_grp <- list(grp1=tbl2grp(1), grp2=tbl2grp(2))

    rowtag <- row.names(res)
    res <- cbind(peakbed[rowtag, ], norm_count_grp$grp1[rowtag], norm_count_grp$grp2[rowtag], res[rowtag, ])
    write.table(res, paste(paste(prefix, "tmp", sep="."), "diffbind.bed.tmp", sep="/"), sep="	", row.names=F, col.names=F, quote=F)
EOF
}

make_igv() {
  count_error
  qsortBed -t $PREFIX.tmp/tmp4sort $PREFIX.tmp/diffbind.bed.tmp| tee $PREFIX.bed| \
  awk -F"	" -v OFS="	" -v LABEL1="${GROUP_LBL_USER[0]}" -v LABEL2="${GROUP_LBL_USER[1]}" \
    -v SRX_LST1="${SRX_LST[0]}" -v SRX_LST2="${SRX_LST[1]}" \
    -v GENOME="$GENOME" -v thres="$BedTHRES" -v PROJECT_NAME="$PROJECT_NAME" '
  BEGIN {
    print "track name=\""PROJECT_NAME"\" gffTags=\"on\""
  } $8 < -1 {
    RGB = "NONE"
    inverse_log2fc = $6 * (-1)
    metadata = "Analysis%20title="PROJECT_NAME";Genome="GENOME";SRXs%20("LABEL1")="SRX_LST1";SRXs%20("LABEL2")="SRX_LST2";Normalized%20count%20("LABEL1")="$4";Normalized%20count%20("LABEL2")="$5";Log2("LABEL1"/"LABEL2")="inverse_log2fc";Log%20P-val="$7";Log%20Q-val="$8
    score = -$8   # score = -log10Q
    if (inverse_log2fc > 0) {        # when SRX1 > SRX2，orange     in edgeR, logfc is calculated by g2/g1.
      R = 222; G = 131; B = 68; #222,131,68
    } else if (inverse_log2fc < 0) {    # when SRX1 < SRX2，blue
      R = 106; G = 153; B = 208; #106,153,208
    }
    RGB = int(R)","int(G)","int(B)
    if (RGB != "NONE") print $1, $2, $3, metadata, score, ".", $2, $3, RGB
  }' > $PREFIX.igv.bed
}

srx_to_trackname() {
  cat /home/okishinya/chipatlas/lib/assembled_list/experimentList.tab| awk -F"	" -v OFS="	" \
  -v GENOME="$GENOME" -v SRX_LST=$(echo ${SRX_LST[@]}| tr ' ' ',') '
  BEGIN {
    c = split(SRX_LST, tmp, ",")
    for (i=1; i<=c; i++) id[tmp[i]]++
  } ($2 == GENOME) && ($1 in id) {
    print $1, $4" (@ "$6") "$1
  }'
} > $PREFIX.tmp/srx_to_trackname

make_igv_session() {
  echo ""| awk -F"	" -v GENOME="$GENOME" -v WABIID="$WABIID" -v cmd="cat $PREFIX.tmp/srx_to_trackname" -v cmd2="cat $URLMETA" -v PROJECT_NAME="$PROJECT_NAME" \
    -v SRX_LST0=$(echo ${SRX_LST[0]}| tr ' ' ',') -v SRX_LST1=$(echo ${SRX_LST[1]}| tr ' ' ',') '
  BEGIN {
    c0 = split(SRX_LST0, srx0, ",")
    c1 = split(SRX_LST1, srx1, ",")
    while (cmd| getline) track[$1] = $2
    refseq["hg38"] = "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/database/ncbiRefSeq.txt.gz"
    refseq["hg19"] = "https://hgdownload.soe.ucsc.edu/goldenPath/hg19/database/ncbiRefSeq.txt.gz"
    refseq["mm10"] = "https://hgdownload.soe.ucsc.edu/goldenPath/mm10/database/ncbiRefSeq.txt.gz"
    refseq["mm9"] = "https://s3.amazonaws.com/igv.org.genomes/mm9/refGene.sorted.txt.gz"
    refseq["rn6"] = "https://s3.amazonaws.com/igv.org.genomes/rn6/ncbiRefSeq.sorted.txt.gz"
    refseq["dm6"] = "https://s3.amazonaws.com/igv.org.genomes/dm6/ncbiRefSeq.txt.gz"
    refseq["dm3"] = "https://s3.amazonaws.com/igv.org.genomes/dm3/refGene.txt.gz"
    refseq["ce11"] = "https://s3.amazonaws.com/igv.org.genomes/ce11/refGene.sorted.txt.gz"
    refseq["ce10"] = "ce10_genes"
    refseq["sacCer3"] = "https://s3.amazonaws.com/igv.org.genomes/sacCer3/ncbiRefSeq.txt.gz"
    while (cmd2| getline) url[$1] = $2
  } {
    print "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>"
    print "<Session genome=\""GENOME"\" locus=\"All\" nextAutoscaleGroup=\"1\" version=\"8\">"

    print "  <Resources>"
    for (i=1; i<=c0; i++) {
      if (srx0[i] ~ "url") print "    <Resource name=\""srx0[i]".bw\" path=\""url[srx0[i]]"\" type=\"bw\"/>\""
      else print "    <Resource name=\""track[srx0[i]]"\" path=\"https://chip-atlas.dbcls.jp/data/"GENOME"/eachData/bw/"srx0[i]".bw\" type=\"bw\"/>\""
    }
    for (i=1; i<=c1; i++) {
      if (srx1[i] ~ "url") print "    <Resource name=\""srx1[i]".bw\" path=\""url[srx1[i]]"\" type=\"bw\"/>\""
      else print "    <Resource name=\""track[srx1[i]]"\" path=\"https://chip-atlas.dbcls.jp/data/"GENOME"/eachData/bw/"srx1[i]".bw\" type=\"bw\"/>\""
    }
    print "    <Resource path=\"https://chip-atlas.dbcls.jp/data/query/"WABIID".igv.bed\" type=\"bed\"/>"
    print "  </Resources>"

    print "  <Panel height=\"40\" name=\"DataPanel\" width=\"1000\">"
    print "    <Track attributeKey=\"Reference sequence\" clazz=\"org.broad.igv.track.SequenceTrack\" fontSize=\"10\" id=\"Reference sequence\" name=\"Reference sequence\" sequenceTranslationStrandValue=\"POSITIVE\" shouldShowTranslation=\"true\" visible=\"true\"/>"
    print "    <Track attributeKey=\"Refseq Genes\" clazz=\"org.broad.igv.track.FeatureTrack\" color=\"51,51,51\" colorScale=\"ContinuousColorScale;0.0;101.0;255,255,255;0,0,178\" fontSize=\"10\" groupByStrand=\"false\" height=\"40\" id=\""refseq[GENOME]"\" name=\"Refseq Genes\" visible=\"true\"/>"
    print "  </Panel>"

    print "  <Panel height=\"40\" name=\"BigWigPanal1\" width=\"1000\">"
    for (i=1; i<=c0; i++) {
      if (srx0[i] ~ "url") print "    <Track attributeKey=\""srx0[i]".bw\" autoScale=\"false\" autoscaleGroup=\"2\" clazz=\"org.broad.igv.track.DataSourceTrack\" color=\"222,131,68\" fontSize=\"10\" height=\"40\" id=\""url[srx0[i]]"\" name=\""srx0[i]".bw\" renderer=\"BAR_CHART\" visible=\"true\" windowFunction=\"mean\">"
      else print "    <Track attributeKey=\""track[srx0[i]]"\" autoScale=\"false\" autoscaleGroup=\"2\" clazz=\"org.broad.igv.track.DataSourceTrack\" color=\"222,131,68\" fontSize=\"10\" height=\"40\" id=\"https://chip-atlas.dbcls.jp/data/"GENOME"/eachData/bw/"srx0[i]".bw\" name=\""track[srx0[i]]"\" renderer=\"BAR_CHART\" visible=\"true\" windowFunction=\"mean\">"
      print "      <DataRange baseline=\"0.0\" drawBaseline=\"true\" flipAxis=\"false\" maximum=\"1\" minimum=\"0.0\" type=\"LINEAR\"/>"
      print "    </Track>"
    }
    print "  </Panel>"

    print "  <Panel height=\"40\" name=\"BigWigPanal2\" width=\"1000\">"
    for (i=1; i<=c1; i++) {
      if (srx1[i] ~ "url") print "    <Track attributeKey=\""srx1[i]".bw\" autoScale=\"false\" autoscaleGroup=\"2\" clazz=\"org.broad.igv.track.DataSourceTrack\" color=\"222,131,68\" fontSize=\"10\" height=\"40\" id=\""url[srx1[i]]"\" name=\""srx1[i]".bw\" renderer=\"BAR_CHART\" visible=\"true\" windowFunction=\"mean\">"
      else print "    <Track attributeKey=\""track[srx1[i]]"\" autoScale=\"false\" autoscaleGroup=\"2\" clazz=\"org.broad.igv.track.DataSourceTrack\" color=\"106,153,208\" fontSize=\"10\" height=\"40\" id=\"https://chip-atlas.dbcls.jp/data/"GENOME"/eachData/bw/"srx1[i]".bw\" name=\""track[srx1[i]]"\" renderer=\"BAR_CHART\" visible=\"true\" windowFunction=\"mean\">"
      print "      <DataRange baseline=\"0.0\" drawBaseline=\"true\" flipAxis=\"false\" maximum=\"1\" minimum=\"0.0\" type=\"LINEAR\"/>"
      print "    </Track>"
    }
    print "  </Panel>"

    print "  <Panel height=\"40\" name=\"FeaturePanel\" width=\"1000\">"
    print "    <Track attributeKey=\""WABIID".igv.bed\" clazz=\"org.broad.igv.track.FeatureTrack\" colorScale=\"ContinuousColorScale;0.0;56.0;255,255,255;0,0,178\" fontSize=\"10\" groupByStrand=\"false\" id=\"https://chip-atlas.dbcls.jp/data/query/"WABIID".igv.bed\" name=\""PROJECT_NAME"\" visible=\"true\"/>"
    print "  </Panel>"

    print "  <PanelLayout dividerFractions=\"0.1,0.45,0.8\"/>"
    print "  <HiddenAttributes>"
    print "    <Attribute name=\"DATA FILE\"/>"
    print "    <Attribute name=\"DATA TYPE\"/>"
    print "    <Attribute name=\"NAME\"/>"
    print "  </HiddenAttributes>"
    print "</Session>"
  }' > $PREFIX.igv.xml
}

count_diffbind() {
  count_error
  End_jst=$(date "+%Y-%m-%dT%H:%M:%S+0900 (JST)")
  End_utc=$(date --utc "+%Y-%m-%dT%H:%M:%SZ (UTC)")
  cat $PREFIX.bed| awk -F"	" -v OFS="	" \
  -v LABEL1="${GROUP_LBL_USER[0]}" -v LABEL2="${GROUP_LBL_USER[1]}" -v Start_jst="$Start_jst" -v Start_utc="$Start_utc" -v End_jst="$End_jst" -v End_utc="$End_utc" '{
    if ($8 < -1) {
      if      ($6 < 0) label2_lt_label1++
      else if ($6 > 0) label1_lt_label2++
    }
  } END {
    print ""
    print "========= Finished! ========="
    print ""
    print "Count of detected diffpeak regions (Q-value < 0.1)"
    print "  Number of specific peaks to \""LABEL1"\" = "label2_lt_label1++
    print "  Number of specific peaks to \""LABEL2"\" = "label1_lt_label2++
    print ""
    print "Start = "Start_jst"; "Start_utc
    print "End = "End_jst"; "End_utc
  }' >> $LOGFILE
}

rm_tmp() {
  rm -fr $PREFIX.tmp
}

main() {
  define_variables
  add_parameters_to_log
  load_urls
  init_log
  check_srx_and_genome_is_not_empty
  get_gsm2srx
  check_srx_genome_pair_is_correct
  do_gsm2srx
  def_var2
  check_bw_exist
  get_peak_list
  get_meta

  echo "bigWig to count table ... " >> $LOGFILE
  echo "" >> $LOGFILE

  bw_to_count ${SRX_LST[0]} &
  PIDs+=($!)
  bw_to_count ${SRX_LST[1]} &
  PIDs+=($!)
  wait ${PIDs[@]}

  get_count_list
  combine_count_tbl

  getDegs "$PREFIX.tmp/count.tsv" "$LABELS" "$PREFIX.tmp/peak_list.bed" "$PREFIX" # > /dev/null 2>&1
  make_igv
  srx_to_trackname
  make_igv_session
  count_diffbind >> $LOGFILE
  rm_tmp
  exit 0
}

# Run
main
