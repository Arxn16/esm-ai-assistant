class AddProjectInheritanceToEsmProjects < ActiveRecord::Migration
  def change
    add_column :esm_projects, :extended, :string
    add_column :esm_projects, :extended_acl_id, :integer
  end
end
