class AddSerivceIdToEsmDocuments < ActiveRecord::Migration
  def change
    add_column :esm_documents, :service_id, :integer
  end
end
