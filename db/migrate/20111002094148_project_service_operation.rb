class ProjectServiceOperation < ActiveRecord::Migration
  def up
          create_table "esm_operations", :force => true do |t|
              t.string   "name"
              t.integer  "service_id"
              t.integer  "template_id"
           
              
              t.text     "command"
              t.text     "description"
              t.boolean  "auto_test"
              t.string   "snippet"
              
              t.datetime "created_at"
              t.datetime "updated_at"
              
              
            end

            create_table "esm_projects", :force => true do |t|
              t.string   "name"
              t.string   "package"
              t.text     "description"
              
              t.integer  "user_id"
              t.integer  "database_id"        
                
              t.text     "dependencies"
              t.text   "params"
              
              t.integer  "esm_id"
              t.datetime "created_at"
              t.datetime "updated_at"
            end
            
            create_table "esm_services", :force => true do |t|
               t.string   "name"
               t.string   "package"
               t.text     "description"
               t.string   "params"
               t.datetime "created_at"
               t.datetime "updated_at"
               t.string  "service_id"
               t.text     "cache"
               t.integer  "user_id"
               t.integer  "project_id"
             end


             create_table "esm_templates", :force => true do |t|
                t.string   "name"
                t.text     "generator"
                t.text     "template"
                t.datetime "created_at"
                t.datetime "updated_at"
              end
             
  end

  def down
  end
end
