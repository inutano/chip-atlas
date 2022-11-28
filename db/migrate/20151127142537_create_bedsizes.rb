class CreateBedsizes < ActiveRecord::Migration[7.0]
  def change
    create_table(:bedsizes) do |t|
      t.string :genome
      t.string :agClass
      t.string :clClass
      t.string :qval
      t.integer :number_of_lines
      t.timestamp
    end
    [ :genome, :agClass, :clClass, :qval, :number_of_lines ].each do |column|
      add_index :bedsizes, column
    end
  end
end
