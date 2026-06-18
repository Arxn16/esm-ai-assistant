class AddProjectToMenuActions < ActiveRecord::Migration
  def change
    add_column :menu_actions, :project_id, :integer
  end
end
