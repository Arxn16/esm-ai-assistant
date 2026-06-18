class CreateEsmTables < ActiveRecord::Migration
  def change
    create_table :esm_tables do |t|
      t.integer :esm_id
      t.integer :schema_id
      t.string :name
      t.text :data
      
      t.timestamps
    end
  end
end
