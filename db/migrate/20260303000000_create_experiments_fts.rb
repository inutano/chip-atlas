class CreateExperimentsFts < ActiveRecord::Migration[4.2]
  def up
    execute <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS experiments_fts USING fts5(
        expid, sra_id, geo_id, genome, agClass, agSubClass,
        clClass, clSubClass, title, attributes
      )
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS experiments_fts"
  end
end
