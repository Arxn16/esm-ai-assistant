# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20260618130000) do

  create_table "accounts", force: :cascade do |t|
    t.integer  "esm_id",     limit: 4
    t.integer  "role_id",    limit: 4
    t.integer  "user_id",    limit: 4
    t.datetime "expired_at"
    t.boolean  "active",     limit: 1
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "esm_document_versions", force: :cascade do |t|
    t.integer  "document_id", limit: 4
    t.integer  "table_id",    limit: 4
    t.text     "data",        limit: 16777215
    t.text     "tree_data",   limit: 16777215
    t.text     "table_data",  limit: 16777215
    t.integer  "author_id",   limit: 4
    t.string   "author_name", limit: 255
    t.string   "source",      limit: 255
    t.text     "note",        limit: 65535
    t.datetime "created_at"
  end

  add_index "esm_document_versions", ["document_id"], name: "index_esm_document_versions_on_document_id", using: :btree

  create_table "esm_documents", force: :cascade do |t|
    t.string   "name",          limit: 255
    t.string   "document_type", limit: 255
    t.text     "data",          limit: 65535
    t.integer  "user_id",       limit: 4
    t.integer  "project_id",    limit: 4
    t.integer  "table_id",      limit: 4
    t.integer  "sort_order",    limit: 4
    t.boolean  "published",     limit: 1
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "title",         limit: 255
    t.integer  "service_id",    limit: 4
    t.text     "tree_data",     limit: 65535
    t.boolean  "ai_editable",   limit: 1,     default: false
  end

  add_index "esm_documents", ["project_id"], name: "document_project_id", using: :btree

  create_table "esm_operations", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.integer  "service_id",  limit: 4
    t.integer  "template_id", limit: 4
    t.text     "command",     limit: 65535
    t.text     "description", limit: 65535
    t.boolean  "auto_test",   limit: 1
    t.string   "snippet",     limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "title",       limit: 255
    t.string   "acl",         limit: 255
  end

  add_index "esm_operations", ["service_id"], name: "operation_service_id", using: :btree

  create_table "esm_projects", force: :cascade do |t|
    t.string   "name",            limit: 255
    t.string   "package",         limit: 255
    t.text     "description",     limit: 65535
    t.integer  "user_id",         limit: 4
    t.integer  "database_id",     limit: 4
    t.text     "dependencies",    limit: 65535
    t.text     "params",          limit: 65535
    t.integer  "esm_id",          limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "domain",          limit: 255
    t.string   "title",           limit: 255
    t.string   "extended",        limit: 255
    t.integer  "extended_acl_id", limit: 4
    t.string   "acl",             limit: 255
  end

  add_index "esm_projects", ["esm_id", "name"], name: "project_esm_name", using: :btree
  add_index "esm_projects", ["package"], name: "project_package", using: :btree

  create_table "esm_schemas", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.integer  "esm_id",      limit: 4
    t.integer  "project_id",  limit: 4
    t.string   "schema_type", limit: 255
    t.string   "source",      limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "esm_schemas", ["name"], name: "schema_name", using: :btree
  add_index "esm_schemas", ["project_id"], name: "schema_project_id", using: :btree

  create_table "esm_services", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.string   "package",     limit: 255
    t.text     "description", limit: 65535
    t.string   "params",      limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "extended",    limit: 255
    t.text     "cache",       limit: 65535
    t.integer  "user_id",     limit: 4
    t.integer  "project_id",  limit: 4
    t.string   "title",       limit: 255
    t.string   "acl",         limit: 255
  end

  add_index "esm_services", ["name"], name: "service_name", using: :btree
  add_index "esm_services", ["package"], name: "service_package", using: :btree
  add_index "esm_services", ["project_id"], name: "service_project_id", using: :btree

  create_table "esm_tables", force: :cascade do |t|
    t.integer  "esm_id",     limit: 4
    t.integer  "schema_id",  limit: 4
    t.string   "name",       limit: 255
    t.text     "data",       limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "command",    limit: 65535
  end

  add_index "esm_tables", ["schema_id"], name: "table_schema_id", using: :btree

  create_table "esm_templates", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.text     "generator",  limit: 65535
    t.text     "template",   limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "esms", force: :cascade do |t|
    t.string   "name",            limit: 255
    t.string   "title",           limit: 255
    t.string   "url",             limit: 255
    t.integer  "user_id",         limit: 4
    t.integer  "sort_order",      limit: 4
    t.boolean  "published",       limit: 1,   default: true
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "default_project", limit: 255
  end

  add_index "esms", ["name"], name: "esm_name", using: :btree
  add_index "esms", ["url"], name: "esm_url", using: :btree

  create_table "logs", force: :cascade do |t|
    t.integer  "user_id",    limit: 4
    t.integer  "role_id",    limit: 4
    t.string   "remote_ip",  limit: 255
    t.string   "action",     limit: 255
    t.string   "path",       limit: 255
    t.string   "remark",     limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "esm_id",     limit: 4
  end

  create_table "menu_actions", force: :cascade do |t|
    t.string   "name",            limit: 255
    t.string   "label",           limit: 255
    t.string   "action_category", limit: 255
    t.integer  "parent_id",       limit: 4
    t.string   "action_type",     limit: 255
    t.string   "url",             limit: 255
    t.integer  "sort_order",      limit: 4
    t.boolean  "published",       limit: 1,   default: true
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "esm_id",          limit: 4
    t.integer  "project_id",      limit: 4
    t.string   "title",           limit: 255
    t.string   "acl",             limit: 255
  end

  create_table "permissions", force: :cascade do |t|
    t.string   "name",           limit: 255
    t.integer  "menu_action_id", limit: 4
    t.integer  "role_id",        limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "roles", force: :cascade do |t|
    t.string   "name",         limit: 255
    t.string   "description",  limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "default_home", limit: 255
    t.integer  "esm_id",       limit: 4
    t.integer  "project_id",   limit: 4
  end

  create_table "settings", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.string   "value",       limit: 255
    t.string   "description", limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "esm_id",      limit: 4
    t.integer  "project_id",  limit: 4
    t.string   "group",       limit: 255
  end

  add_index "settings", ["project_id"], name: "setting_project_id", using: :btree

  create_table "users", force: :cascade do |t|
    t.string   "login",           limit: 255
    t.string   "hashed_password", limit: 255
    t.string   "email",           limit: 255
    t.string   "salt",            limit: 255
    t.datetime "last_accessed"
    t.boolean  "activate",        limit: 1
    t.integer  "role_id",         limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "esm_id",          limit: 4
    t.string   "name",            limit: 255
    t.datetime "last_actived"
    t.string   "current_session", limit: 255
  end

end
