# frozen_string_literal: true

class CreateCacheEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :cache_entries, id: false do |t|
      t.string :ns, null: false
      t.string :key, null: false
      t.text :value_json
      t.string :version
      t.string :etag
      t.string :last_modified
      t.integer :fetched_at, null: false
      t.integer :verified_at
      t.integer :expires_at
      t.integer :stale_until
      t.integer :size, null: false, default: 0
      t.integer :accessed_at
    end

    add_index :cache_entries, %i[ns key], unique: true
  end
end
