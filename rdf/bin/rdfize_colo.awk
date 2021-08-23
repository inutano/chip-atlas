#! /usr/bin/env awk -f
# Usage:
#  $ rdfize_colo.awk <ID mapping table file> <ChIP-Atlas colocalization file(s)>
#
# ID mapping table file format:
# <Gene symbol><tab><RefSeq ID><tab><Ensembl Gene ID>

BEGIN {
    OFS = "\t"
    FS = "\t"

    print "@prefix ca:   <http://chip-atlas.org/resources/> ."
    print "@prefix cao:  <http://chip-atlas.org/ontology/> ."
    print "@prefix ensg: <http://identifiers.org/ensembl/> ."
    print "@prefix srx:  <http://identifiers.org/insdc.sra/> ."
    print ""
}

FNR==1 {
    fn++
}

# ID mapping table file
fn==1 {
    if($3)
        sym2id[$1] = gensub(/\.[0-9]+$/, "", "g", $3)
}

# ChIP-Atlas colocalization file(s)
fn>=2 && FNR==1 {
    for(i=5; i<=NF-1; i++) {
        split($i, s, "|")
        exp_id[i] = s[1]
        cell_line[i] = s[2]
    }
    split(gensub(/^.*\//, "", "g", FILENAME), s, ".") # <TF>.<tissue>.tsv
    tf_sym = s[1]
    if(sym2id[tf_sym]) {
        tf_id = sym2id[tf_sym]
    }
    else {
        print "ERROR: " FILENAME " exists but " tf_sym " is not defined in the ID mapping table file." > "/dev/stderr"
        nextfile
    }
}

fn>=2 && FNR>=2 {
    if(sym2id[$3]) {
        partner_id = sym2id[$3]
        for(i=5; i<=NF-1; i++) {
            relation_id = exp_id[i] "-" $1
            print "ca:" relation_id " a cao:Colocalization ;"
            print "  cao:hasTF ensg:" tf_id " ;"
            print "  cao:hasPartner ensg:" partner_id " ;"
            print "  cao:hasExperiment srx:" exp_id[i] " ;"
            print "  cao:hasPartnerExp srx:" $1 " ;"
            print "  cao:coloScore " $i " ;"
            print "  cao:hasCellLine \"" cell_line[i] "\" ;"
            print "  cao:hasPartnerCellLine \"" $2 "\" .\n"
        }
    } else {
        print FILENAME ":" FNR ": " $3 " is not defined in the ID mapping table file." > "/dev/stderr"
        next
        # print $1
    }
}
