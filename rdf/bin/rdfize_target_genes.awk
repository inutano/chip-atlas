#! /usr/bin/env awk -f
# Usage:
#  $ rdfize_target_genes.awk <ID mapping table file> <ChIP-Atlas target genes file(s)>
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

# ChIP-Atlas target genes file(s)
fn>=2 && FNR==1 {
    for(i=3; i<=NF-1; i++) {
        split($i, s, "|")
        exp_id[i] = s[1]
        cell_line[i] = s[2]
    }
    split(gensub(/^.*\//, "", "g", FILENAME), s, ".") # <TF>.(1|5|10).tsv
    #tf_sym = gensub(/(^.*\/)|(\.[0-9]+\.tsv)/, "", "g", FILENAME)
    tf_sym = s[1]
    range = s[2]
    if(sym2id[tf_sym]) {
        tf_id = sym2id[tf_sym]
    }
    else {
        print "ERROR: " FILENAME " exists but " tf_sym " is not defined in the ID mapping table file." > "/dev/stderr"
        nextfile
    }
}

fn>=2 && FNR>=2 {
    if(sym2id[$1]) {
        target_id = sym2id[$1]
        for(i=3; i<=NF-1; i++) {
            if($i == 0)
                continue
            relation_id = exp_id[i] "-" target_id
            if(!is_covered_id[relation_id]) {
                is_covered_id[relation_id] = 1
                print "ca:" relation_id " a cao:PutativeRegulation ;"
                print "  cao:hasTF ensg:" tf_id " ;"
                print "  cao:hasTargetGene ensg:" target_id " ;"
                print "  cao:score" range "k " $i " ;"
                print "  cao:hasExperiment srx:" exp_id[i] " ;"
                print "  cao:hasCellLine \"" cell_line[i] "\" .\n"
            } else {
                print "ca:" relation_id " cao:score" range "k " $i " .\n"
            }
        }
    } else {
        print FILENAME ":" FNR ": " $1 " is not defined in the ID mapping table file." > "/dev/stderr"
        next
        # print $1
    }
}
