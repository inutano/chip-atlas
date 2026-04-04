# frozen_string_literal: true

Sequel.migration do
  up do
    create_table :experiments do
      primary_key :id
      String :experiment_id, null: false
      String :genome, null: false
      String :track_class
      String :track_subclass
      String :cell_type_class
      String :cell_type_subclass
      String :cell_type_subclass_info
      String :read_info
      String :title
      String :attributes, text: true
      DateTime :created_at

      index :experiment_id
      index :genome
      index :track_class
      index :track_subclass
      index :cell_type_class
      index :cell_type_subclass
      index [:genome, :track_class]
      index [:genome, :track_class, :cell_type_class]
    end

    create_table :bedfiles do
      primary_key :id
      String :filename, null: false
      String :genome, null: false
      String :track_class
      String :track_subclass
      String :cell_type_class
      String :cell_type_subclass
      String :qval
      String :experiments, text: true
      DateTime :created_at

      index :genome
      index [:genome, :track_class, :track_subclass, :cell_type_class, :cell_type_subclass, :qval],
            name: :idx_bedfiles_lookup
    end

    create_table :bedsizes do
      primary_key :id
      String :genome, null: false
      String :track_class
      String :cell_type_class
      String :qval
      Bignum :number_of_lines
      DateTime :created_at

      index [:genome, :track_class, :cell_type_class, :qval], name: :idx_bedsizes_lookup
    end

    create_table :analyses do
      primary_key :id
      String :track
      String :cell_list, text: true
      TrueClass :target_genes
      String :genome, null: false
      DateTime :created_at

      index :track
      index :genome
      index :target_genes
    end

    create_table :runs do
      primary_key :id
      String :run_id, null: false
      String :experiment_id, null: false
      DateTime :created_at

      index :run_id
      index :experiment_id
    end

    create_table :sra_cache do
      primary_key :id
      String :experiment_id, null: false, unique: true
      String :metadata_json, text: true
      DateTime :fetched_at
      DateTime :created_at
    end

    run <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS experiments_fts USING fts5(
        experiment_id,
        sra_id,
        geo_id,
        genome,
        track_class,
        track_subclass,
        cell_type_class,
        cell_type_subclass,
        title,
        attributes
      );
    SQL
  end

  down do
    run "DROP TABLE IF EXISTS experiments_fts"
    drop_table :sra_cache
    drop_table :runs
    drop_table :analyses
    drop_table :bedsizes
    drop_table :bedfiles
    drop_table :experiments
  end
end
