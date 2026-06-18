class CreateEsmSchemas < ActiveRecord::Migration
  def change
    create_table :esm_schemas do |t|
      t.string :name
      t.integer :esm_id
      t.integer :project_id
      t.string :schema_type
      t.string :source

      t.timestamps
    end
  end
end
