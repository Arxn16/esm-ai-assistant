class AddTreeDataToEsmDocuments < ActiveRecord::Migration
  def change
    add_column :esm_documents, :tree_data, :text
  end
end
