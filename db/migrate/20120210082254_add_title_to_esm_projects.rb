class AddTitleToEsmProjects < ActiveRecord::Migration
  def change
    add_column :esm_projects, :title, :string
    add_column :esm_services, :title, :string
    add_column :esm_operations, :title, :string
    add_column :esm_documents, :title, :string
    add_column :menu_actions, :title, :string
    
  end
end
