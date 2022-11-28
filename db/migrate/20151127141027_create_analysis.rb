class CreateAnalysis < ActiveRecord::Migration[7.0]
  def change
    create_table(:analyses) do |t|
      t.string :antigen
      t.string :cell_list
      t.boolean :target_genes
      t.string :genome
      t.timestamp
    end
    [ :antigen, :cell_list, :target_genes, :genome ].each do |column|
      add_index :analyses, column
    end
  end
end
