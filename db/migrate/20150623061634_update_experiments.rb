class UpdateExperiments < ActiveRecord::Migration[4.2]
  def up
    add_column :experiments, :clSubClassInfo, :string
    add_column :experiments, :readInfo, :string
  end

  def down
  end
end
