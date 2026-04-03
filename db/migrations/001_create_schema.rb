Sequel.migration do
  up do
    create_table :experiments do
      primary_key :id
      String :exp_id, null: false
      String :genome, null: false
      String :ag_class
      String :ag_sub_class
      String :cl_class
      String :cl_sub_class
      String :cl_sub_class_info
      String :read_info
      String :title
      String :attributes, text: true
      DateTime :created_at

      index :exp_id
      index :genome
      index :ag_class
      index :ag_sub_class
      index :cl_class
      index :cl_sub_class
      index [:genome, :ag_class]
      index [:genome, :ag_class, :cl_class]
    end

    create_table :bedfiles do
      primary_key :id
      String :filename, null: false
      String :genome, null: false
      String :ag_class
      String :ag_sub_class
      String :cl_class
      String :cl_sub_class
      String :qval
      String :experiments, text: true
      DateTime :created_at

      index :genome
      index [:genome, :ag_class, :ag_sub_class, :cl_class, :cl_sub_class, :qval],
            name: :idx_bedfiles_lookup
    end

    create_table :bedsizes do
      primary_key :id
      String :genome, null: false
      String :ag_class
      String :cl_class
      String :qval
      Bignum :number_of_lines
      DateTime :created_at

      index [:genome, :ag_class, :cl_class, :qval], name: :idx_bedsizes_lookup
    end

    create_table :analyses do
      primary_key :id
      String :antigen
      String :cell_list, text: true
      TrueClass :target_genes
      String :genome, null: false
      DateTime :created_at

      index :antigen
      index :genome
      index :target_genes
    end

    create_table :runs do
      primary_key :id
      String :run_id, null: false
      String :exp_id, null: false
      DateTime :created_at

      index :run_id
      index :exp_id
    end

    create_table :sra_cache do
      primary_key :id
      String :exp_id, null: false, unique: true
      String :metadata_json, text: true
      DateTime :fetched_at
      DateTime :created_at
    end

    run <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS experiments_fts USING fts5(
        exp_id,
        sra_id,
        geo_id,
        genome,
        ag_class,
        ag_sub_class,
        cl_class,
        cl_sub_class,
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
