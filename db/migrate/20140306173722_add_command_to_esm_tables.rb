class AddCommandToEsmTables < ActiveRecord::Migration
  def change
    add_column :esm_tables, :command, :text
  end
end
