# frozen_string_literal: true

class AddMetricsAndStrategyIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :cache_events, %i[user_id project_id hit]
    add_index :cache_strategies, %i[project_id namespace],
              unique: true,
              where: "user_id IS NULL AND connection_id IS NULL",
              name: "index_cache_strategies_project_defaults"
    add_index :cache_strategies, %i[project_id user_id namespace],
              unique: true,
              where: "user_id IS NOT NULL AND connection_id IS NULL",
              name: "index_cache_strategies_user_overrides"
    add_index :cache_strategies, %i[project_id connection_id namespace],
              unique: true,
              where: "user_id IS NULL AND connection_id IS NOT NULL",
              name: "index_cache_strategies_connection_overrides"
  end
end
