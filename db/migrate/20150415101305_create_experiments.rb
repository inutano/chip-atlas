class CreateExperiments < ActiveRecord::Migration[7.0]
  def up
    create_table(:experiments) do |t|
      t.string :expid
      t.string :genome
      t.string :agClass
      t.string :agSubClass
      t.string :clClass
      t.string :clSubClass
      t.string :title
      t.string :additional_attributes
      t.timestamp :timestamp
    end
    [ :expid, :agClass, :agSubClass, :clClass, :clSubClass ].each do |field|
      add_index :experiments, field
    end
  end
end
