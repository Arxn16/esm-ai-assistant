class AddGroupToSettings < ActiveRecord::Migration
  def change
    
    add_column :settings, :project_id, :integer
    add_column :settings, :group, :string
    
  end
end
