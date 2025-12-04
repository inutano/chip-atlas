#!/usr/bin/awk

BEGIN {
  while (getline < HTML_TPL) {
    gsub("___Title___", title, $0)
    gsub("___Targets___", desc_a, $0)
    gsub("___References___", desc_b, $0)
    gsub("___Header___", HTML_HEADER, $0)
    gsub("___Caption___", title, $0)
    gsub("___WABIid___", wabi_id, $0)
    print
  }
} {
  print "<tr>"
  print "<td title=\"Open this Info...\"><a target=\"_blank\" style=\"text-decoration: none\" href=\"" SRX_URL $1 "\">" $1 "</a></td>"
  for (i=2; i<=5; i++) print "<td>" $i "</td>"
  for (i=6; i<=8; i++) printf "<td align=\"right\">%s</td>\n", $i
  for (i=9; i<=10; i++) printf "<td align=\"right\">%.1f</td>\n", $i
  printf "<td align=\"right\">%s</td>\n", ($11 == "inf") ? 99999 : sprintf("%.2f", $11)
  printf "<td>%s</td>\n", ($11 > 0) ? "TRUE" : "FALSE"
  print "</tr>"
} END {
  print "</tbody>"
  print "</table>"
}
