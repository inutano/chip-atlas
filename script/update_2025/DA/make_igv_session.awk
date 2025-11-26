#!/usr/bin/awk

function print_bw_tracks(srx, group, id) {
  rgb = (group == "A") ? "222,131,68" : "106,153,208"
  printf "<Track attributeKey=\"%s\" autoScale=\"false\" autoscaleGroup=\"2\" "\
         "clazz=\"org.broad.igv.track.DataSourceTrack\" color=\"%s\" fontSize=\"10\" height=\"40\" "\
         "id=\"%s\" name=\"%s\" renderer=\"BAR_CHART\" visible=\"true\" windowFunction=\"mean\">\n", \
         track[srx], rgb, id, track[srx]
  print "<DataRange baseline=\"0.0\" drawBaseline=\"true\" flipAxis=\"false\" maximum=\"1\" minimum=\"0.0\" type=\"LINEAR\"/>"
  print "</Track>"
} function load_map(filename, map) {
  while ((getline < filename) > 0) map[$1] = $2
} BEGIN {
  refseq_id = genome "_genes"

  # ファイルからデータをロード
  load_map(track_name, track)
  load_map(url_input, url_bw)

  # `method` に応じた URL パターンの決定
  if (method == "dmr") {
    prefix = "https://chip-atlas.dbcls.jp/data/" genome "/eachData/bs/methyl/"
    suffix = ".methyl.bw"
  } else if (method == "diffbind") {
    prefix = "https://chip-atlas.dbcls.jp/data/" genome "/eachData/bw/"
    suffix = ".bw"
  }

  print "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>"
  printf "<Session genome=\"%s\" locus=\"All\" nextAutoscaleGroup=\"1\" version=\"8\">\n", genome
  print "<Resources>"
} {
  if (FNR == 1) group = NR == 1 ? "A" : "B"
  (group == "A") ? group_a[FNR] = $1 : group_b[FNR] = $1

  path = ($1 ~ "URL") ? url_bw[$1] : prefix $1 suffix
  printf "<Resource name=\"%s\" path=\"%s\" type=\"bw\"/>\n", track[$1], path
} END {
  printf "<Resource path=\"%s\" type=\"bed\"/>\n", bed_igv
  print "</Resources>"

  # データパネル
  print "<Panel height=\"40\" name=\"DataPanel\" width=\"1000\">"
  printf "<Track attributeKey=\"Reference sequence\" clazz=\"org.broad.igv.track.SequenceTrack\" fontSize=\"10\" "\
         "id=\"Reference sequence\" name=\"Reference sequence\" sequenceTranslationStrandValue=\"POSITIVE\" "\
         "shouldShowTranslation=\"true\" visible=\"true\"/>\n"

  printf "<Track attributeKey=\"Refseq Genes\" clazz=\"org.broad.igv.track.FeatureTrack\" color=\"51,51,51\" "\
         "colorScale=\"ContinuousColorScale;0.0;101.0;255,255,255;0,0,178\" fontSize=\"10\" groupByStrand=\"false\" "\
         "height=\"40\" id=\"%s\" name=\"Refseq Genes\" visible=\"true\"/>\n", refseq_id
  print "</Panel>"

  # BigWigパネル
  print "<Panel height=\"40\" name=\"BigWigPanel1\" width=\"1000\">"
  for (i=1; i<=length(group_a); i++) {
    srx = group_a[i]
    print_bw_tracks(srx, "A", (srx ~ "URL") ? url_bw[srx] : prefix srx suffix)
  }
  print "</Panel>"

  print "<Panel height=\"40\" name=\"BigWigPanel2\" width=\"1000\">"
  for (i=1; i<=length(group_b); i++) {
    srx = group_b[i]
    print_bw_tracks(srx, "B", (srx ~ "URL") ? url_bw[srx] : prefix srx suffix)
  }
  print "</Panel>"

  # フィーチャーパネル
  print "<Panel height=\"40\" name=\"FeaturePanel\" width=\"1000\">"
  printf "<Track attributeKey=\"%s\" clazz=\"org.broad.igv.track.FeatureTrack\" "\
         "colorScale=\"ContinuousColorScale;0.0;56.0;255,255,255;0,0,178\" "\
         "fontSize=\"10\" groupByStrand=\"false\" id=\"%s\" name=\"%s\" visible=\"true\"/>\n", \
         bed_igv, bed_igv, title
  print "</Panel>"

  # パネルレイアウト
  print "<PanelLayout dividerFractions=\"0.1,0.45,0.8\"/>"
  print "<HiddenAttributes>"
  print "<Attribute name=\"DATA FILE\"/>"
  print "<Attribute name=\"DATA TYPE\"/>"
  print "<Attribute name=\"NAME\"/>"
  print "</HiddenAttributes>"
  print "</Session>"
}
