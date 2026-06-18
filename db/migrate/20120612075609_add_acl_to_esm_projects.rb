class AddAclToEsmProjects < ActiveRecord::Migration
  def change
    add_column :esm_projects, :acl, :string
    add_column :esm_services, :acl, :string
    add_column :esm_operations, :acl, :string
    add_column :menu_actions, :acl, :string
    
  end
end
