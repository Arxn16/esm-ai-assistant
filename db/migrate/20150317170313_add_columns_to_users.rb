class AddColumnsToUsers < ActiveRecord::Migration
  def change
    add_column :users, :name, :string
    add_column :users, :last_actived, :datetime
    add_column :users, :current_session, :string
  end
end
