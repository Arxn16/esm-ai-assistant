class CreateEsmDocuments < ActiveRecord::Migration
  def change
    create_table :esm_documents do |t|
      t.string :name
      t.string :document_type
      t.text :data
      t.integer :user_id
      t.integer :project_id
      t.integer :table_id
      t.integer :sort_order
      t.boolean :published

      t.timestamps
    end
  end
end
