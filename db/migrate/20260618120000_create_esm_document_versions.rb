class CreateEsmDocumentVersions < ActiveRecord::Migration
  def change
    create_table :esm_document_versions do |t|
      t.integer  :document_id
      t.integer  :table_id
      t.text     :data,       :limit => 16777215   # MEDIUMTEXT - document YAML snapshot
      t.text     :tree_data,  :limit => 16777215
      t.text     :table_data, :limit => 16777215   # esm_tables.data snapshot
      t.integer  :author_id
      t.string   :author_name
      t.string   :source                           # 'ai' | 'manual' | 'rollback'
      t.text     :note                             # clinician prompt / suggestion JSON
      t.datetime :created_at                        # immutable; AR auto-sets on create
    end
    add_index :esm_document_versions, :document_id
  end
end
