# frozen_string_literal: true

# experiments never carried sra_id/geo_id - only experiments_fts did, loaded
# from ExperimentList_adv.json. Task A3's reconciliation joins that JSON onto
# experimentList.tab by experiment_id, so the canonical `experiments` row can
# carry them too (see ChipAtlas::Experiment.load_from_files). Nullable: a
# tab row with no matching JSON row (e.g. a synthetic Annotation-tracks id,
# which never appears in the JSON at all) legitimately has neither.
Sequel.migration do
  change do
    alter_table :experiments do
      add_column :sra_id, String
      add_column :geo_id, String
    end
  end
end
