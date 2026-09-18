# frozen_string_literal: true

# Task B1: analysisList.tab rows are (TF.kb, cell_list, target_genes_flag,
# genome) - the trailing ".<kb>" is the TSS distance, not part of the antigen
# name. It used to be stored inline in `track` (e.g. "Stat3.1"), which the
# Target Genes API then handed straight to the frontend picker and, once
# selected, back to /api/target_genes as an unmatchable `track` value. This
# splits the suffix into its own column so `track` is always the bare
# antigen name.
Sequel.migration do
  change do
    add_column :analyses, :distance, String
  end
end
