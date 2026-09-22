# frozen_string_literal: true

# Reverses migration 002. That column existed to hold a TSS distance split
# out of the antigen name, because the build of analysisList.tab this project
# downloaded in September 2026 spelled its rows "Stat3.1" / "Stat3.5" /
# "Stat3.10". That build was broken; the file has carried one row per antigen
# with no distance component since 2015, and the 2026-09-22 rebuild restored
# it. See the note at the top of lib/models/analysis.rb.
#
# The TSS distance itself has not gone anywhere - it is in the result
# filenames (CTCF.1.tsv / .5 / .10) and in Analysis::TARGET_GENES_DISTANCES,
# which is the UI's fixed set of three. It was simply never a property of a
# row in this table, and leaving a column that says otherwise would invite
# the same misreading again.
Sequel.migration do
  up do
    alter_table(:analyses) { drop_column :distance }
  end

  down do
    alter_table(:analyses) { add_column :distance, String }
  end
end
