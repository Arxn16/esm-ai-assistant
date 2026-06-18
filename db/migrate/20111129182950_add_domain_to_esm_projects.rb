class AddDomainToEsmProjects < ActiveRecord::Migration
  def change
    add_column :esm_projects, :domain, :string
    add_column :esms, :default_project, :string
  end
end
