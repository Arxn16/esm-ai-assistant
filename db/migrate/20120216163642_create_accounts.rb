class CreateAccounts < ActiveRecord::Migration
  def change
    create_table :accounts do |t|
      t.integer :esm_id
      t.integer :role_id
      t.integer :user_id
      t.datetime :expired_at
      t.boolean :active

      t.timestamps
    end
  end
end
