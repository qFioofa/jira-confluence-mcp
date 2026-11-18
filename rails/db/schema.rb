# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_18_000006) do
  create_table "audit_events", force: :cascade do |t|
    t.integer "actor_id"
    t.integer "team_id"
    t.string "action", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["team_id", "created_at"], name: "index_audit_events_on_team_id_and_created_at"
    t.index ["team_id"], name: "index_audit_events_on_team_id"
  end

  create_table "cache_events", force: :cascade do |t|
    t.integer "user_id"
    t.integer "project_id"
    t.string "namespace", null: false
    t.boolean "hit", null: false
    t.string "source"
    t.datetime "created_at", null: false
    t.integer "count", default: 1, null: false
    t.index ["project_id", "created_at"], name: "index_cache_events_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_cache_events_on_project_id"
    t.index ["user_id", "project_id", "hit"], name: "index_cache_events_on_user_id_and_project_id_and_hit"
    t.index ["user_id"], name: "index_cache_events_on_user_id"
  end

  create_table "cache_strategies", force: :cascade do |t|
    t.integer "project_id", null: false
    t.integer "user_id"
    t.integer "connection_id"
    t.string "namespace", null: false
    t.integer "ttl_seconds", null: false
    t.integer "stale_grace_seconds", default: 0, null: false
    t.string "version_field"
    t.boolean "enabled", default: true, null: false
    t.string "source", default: "default", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_cache_strategies_on_connection_id"
    t.index ["project_id", "connection_id", "namespace"], name: "index_cache_strategies_connection_overrides", unique: true, where: "user_id IS NULL AND connection_id IS NOT NULL"
    t.index ["project_id", "namespace"], name: "index_cache_strategies_project_defaults", unique: true, where: "user_id IS NULL AND connection_id IS NULL"
    t.index ["project_id", "user_id", "connection_id", "namespace"], name: "index_cache_strategies_on_scope_and_namespace", unique: true
    t.index ["project_id", "user_id", "namespace"], name: "index_cache_strategies_user_overrides", unique: true, where: "user_id IS NOT NULL AND connection_id IS NULL"
    t.index ["project_id"], name: "index_cache_strategies_on_project_id"
    t.index ["user_id"], name: "index_cache_strategies_on_user_id"
  end

  create_table "connections", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "provider", null: false
    t.string "name", null: false
    t.string "base_url", null: false
    t.string "deployment", default: "cloud", null: false
    t.json "settings", default: {}, null: false
    t.string "status", default: "unknown", null: false
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "provider", "base_url"], name: "index_connections_on_team_id_and_provider_and_base_url", unique: true
    t.index ["team_id"], name: "index_connections_on_team_id"
  end

  create_table "mcp_endpoints", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "project_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.json "scopes", default: ["read"], null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_mcp_endpoints_on_project_id"
    t.index ["token_digest"], name: "index_mcp_endpoints_on_token_digest", unique: true
    t.index ["user_id"], name: "index_mcp_endpoints_on_user_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "user_id"], name: "index_memberships_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "presets", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "kind", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.text "query"
    t.string "order_by"
    t.integer "default_limit", default: 20, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "kind", "key"], name: "index_presets_on_project_id_and_kind_and_key", unique: true
    t.index ["project_id"], name: "index_presets_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "jira_connection_id"
    t.integer "confluence_connection_id"
    t.string "slug", null: false
    t.string "name", null: false
    t.json "jira_keys", default: [], null: false
    t.json "spaces", default: [], null: false
    t.string "style", default: "scrum", null: false
    t.json "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cache_generation", default: 0, null: false
    t.index ["confluence_connection_id"], name: "index_projects_on_confluence_connection_id"
    t.index ["jira_connection_id"], name: "index_projects_on_jira_connection_id"
    t.index ["team_id", "slug"], name: "index_projects_on_team_id_and_slug", unique: true
    t.index ["team_id"], name: "index_projects_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.json "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_teams_on_slug", unique: true
  end

  create_table "tool_calls", force: :cascade do |t|
    t.integer "user_id"
    t.integer "project_id"
    t.integer "connection_id"
    t.string "tool", null: false
    t.string "outcome", null: false
    t.float "duration_ms"
    t.string "cache_source"
    t.string "request_id"
    t.datetime "created_at", null: false
    t.index ["connection_id"], name: "index_tool_calls_on_connection_id"
    t.index ["project_id", "created_at"], name: "index_tool_calls_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_tool_calls_on_project_id"
    t.index ["user_id", "created_at"], name: "index_tool_calls_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_tool_calls_on_user_id"
  end

  create_table "user_credentials", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "connection_id", null: false
    t.string "auth_type", default: "api_token", null: false
    t.string "email"
    t.text "secret_ciphertext"
    t.string "secret_last4"
    t.string "status", default: "unknown", null: false
    t.datetime "last_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_user_credentials_on_connection_id"
    t.index ["user_id", "connection_id"], name: "index_user_credentials_on_user_id_and_connection_id", unique: true
    t.index ["user_id"], name: "index_user_credentials_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "audit_events", "teams"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "cache_events", "projects"
  add_foreign_key "cache_events", "users"
  add_foreign_key "cache_strategies", "connections"
  add_foreign_key "cache_strategies", "projects"
  add_foreign_key "cache_strategies", "users"
  add_foreign_key "connections", "teams"
  add_foreign_key "mcp_endpoints", "projects"
  add_foreign_key "mcp_endpoints", "users"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "presets", "projects"
  add_foreign_key "projects", "connections", column: "confluence_connection_id"
  add_foreign_key "projects", "connections", column: "jira_connection_id"
  add_foreign_key "projects", "teams"
  add_foreign_key "tool_calls", "connections"
  add_foreign_key "tool_calls", "projects"
  add_foreign_key "tool_calls", "users"
  add_foreign_key "user_credentials", "connections"
  add_foreign_key "user_credentials", "users"
end
