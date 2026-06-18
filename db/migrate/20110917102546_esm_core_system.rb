class EsmCoreSystem < ActiveRecord::Migration
  def up
    # ok
    create_table "esms", :force => true do |t|
      t.string   "name"
      t.string   "title"
      t.string   "url"
      t.integer "user_id"
      t.integer  "sort_order"
      t.boolean  "published",      :default => true
      t.datetime "created_at"
      t.datetime "updated_at"
    end
    
    # ok
    create_table "menu_actions", :force => true do |t|
      t.string   "name"
      t.string   "label"
      t.string   "action_category"
      t.integer  "parent_id"
      t.string   "action_type"
      t.string   "url"
      t.integer  "sort_order"
      t.boolean  "published",      :default => true
      t.datetime "created_at"
      t.datetime "updated_at"
      
      t.integer  "esm_id"
    end
    
    

    create_table "permissions", :force => true do |t|
      t.string  "name"
      t.integer  "menu_action_id"
      t.integer  "role_id"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    create_table "roles", :force => true do |t|
      t.string   "name"
      t.string   "description"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.string   "default_home"
      t.integer "esm_id"
      t.integer "project_id"
      
    end

    create_table "settings", :force => true do |t|
      t.string   "name"
      t.string   "value"
      t.string   "description"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer "esm_id"
      
    end

    create_table "logs", :force => true do |t|
      t.integer  "user_id"
      t.integer  "role_id"
      t.string   "remote_ip"
      t.string   "action"
      t.string   "path"
      t.string   "remark"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer  "esm_id"
    end

    create_table "users", :force => true do |t|
      t.string   "login"
      t.string   "hashed_password"
      t.string   "email"
      t.string   "salt"
      t.datetime "last_accessed"
      t.boolean  "activate"
      t.integer  "role_id"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer  "esm_id"
      
    end
    
  end

  def down
  end
end
