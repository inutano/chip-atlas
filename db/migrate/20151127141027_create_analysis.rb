class CreateAnalysis < ActiveRecord::Migration[4.2]
  def change
    create_table(:analyses) do |t|
      t.string :antigen
      t.string :cell_list
      t.boolean :target_genes
      t.string :genome
      t.timestamp :timestamp
    end
    [ :antigen, :cell_list, :target_genes, :genome ].each do |column|
      add_index :analyses, column
    end
  end
end
