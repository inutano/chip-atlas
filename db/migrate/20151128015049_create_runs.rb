class CreateRuns < ActiveRecord::Migration[4.2]
  def change
    create_table(:runs) do |t|
      t.string :runid
      t.string :expid
      t.timestamp :timestamp
    end
    [ :runid, :expid ].each do |column|
      add_index :runs, column
    end
  end
end
