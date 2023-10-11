class CreateBedfiles < ActiveRecord::Migration[4.2]
  def up
    create_table(:bedfiles) do |t|
      t.string :filename
      t.string :genome
      t.string :agClass
      t.string :agSubClass
      t.string :clClass
      t.string :clSubClass
      t.string :qval
      t.string :experiments
      t.timestamp :timestamp
    end
    [ :genome, :agClass, :agSubClass, :clClass, :clSubClass, :qval ].each do |field|
      add_index :bedfiles, field
    end
  end
end
