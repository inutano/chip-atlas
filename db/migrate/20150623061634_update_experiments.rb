class UpdateExperiments < ActiveRecord::Migration
  def up
    add_column :experiments, :clSubClassInfo, :string
    add_column :experiments, :readInfo, :string
  end

  def down
  end
end
