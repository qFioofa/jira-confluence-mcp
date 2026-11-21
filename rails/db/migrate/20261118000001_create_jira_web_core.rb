# frozen_string_literal: true

class CreateJiraWebCore < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name
      t.boolean :admin, null: false, default: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :teams do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.json :settings, null: false, default: {}
      t.timestamps
    end
    add_index :teams, :slug, unique: true

    create_table :memberships do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :memberships, %i[team_id user_id], unique: true

    create_table :connections do |t|
      t.references :team, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :deployment, null: false, default: "cloud"
      t.json :settings, null: false, default: {}
      t.string :status, null: false, default: "unknown"
      t.datetime :last_checked_at
      t.timestamps
    end
    add_index :connections, %i[team_id provider base_url], unique: true

    create_table :projects do |t|
      t.references :team, null: false, foreign_key: true
      t.references :jira_connection, foreign_key: { to_table: :connections }
      t.references :confluence_connection, foreign_key: { to_table: :connections }
      t.string :slug, null: false
      t.string :name, null: false
      t.json :jira_keys, null: false, default: []
      t.json :spaces, null: false, default: []
      t.string :style, null: false, default: "scrum"
      t.json :settings, null: false, default: {}
      t.timestamps
    end
    add_index :projects, %i[team_id slug], unique: true

    create_table :user_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      t.string :auth_type, null: false, default: "api_token"
      t.string :email
      t.text :secret_ciphertext
      t.string :secret_last4
      t.datetime :expires_at
      t.string :status, null: false, default: "unknown"
      t.datetime :last_verified_at
      t.timestamps
    end
    add_index :user_credentials, %i[user_id connection_id], unique: true

    create_table :presets do |t|
      t.references :project, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :key, null: false
      t.string :label, null: false
      t.text :query
      t.string :order_by
      t.integer :default_limit, null: false, default: 20
      t.text :description
      t.timestamps
    end
    add_index :presets, %i[project_id kind key], unique: true

    create_table :mcp_endpoints do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.json :scopes, null: false, default: ["read"]
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :mcp_endpoints, :token_digest, unique: true

    create_table :cache_strategies do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :connection, foreign_key: true
      t.string :namespace, null: false
      t.integer :ttl_seconds, null: false
      t.integer :stale_grace_seconds, null: false, default: 0
      t.string :version_field
      t.boolean :enabled, null: false, default: true
      t.string :source, null: false, default: "default"
      t.timestamps
    end
    add_index :cache_strategies, %i[project_id user_id connection_id namespace],
              unique: true, name: "index_cache_strategies_on_scope_and_namespace"

    create_table :tool_calls do |t|
      t.references :user, foreign_key: true
      t.references :project, foreign_key: true
      t.references :connection, foreign_key: true
      t.string :tool, null: false
      t.string :outcome, null: false
      t.float :duration_ms
      t.string :cache_source
      t.string :request_id
      t.datetime :created_at, null: false
    end
    add_index :tool_calls, %i[project_id created_at]
    add_index :tool_calls, %i[user_id created_at]

    create_table :cache_events do |t|
      t.references :user, foreign_key: true
      t.references :project, foreign_key: true
      t.string :namespace, null: false
      t.boolean :hit, null: false
      t.string :source
      t.datetime :created_at, null: false
    end
    add_index :cache_events, %i[project_id created_at]

    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users }
      t.references :team, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.json :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :audit_events, %i[team_id created_at]
  end
end
