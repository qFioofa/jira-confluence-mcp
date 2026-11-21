# frozen_string_literal: true

class AddCacheGenerationToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :cache_generation, :integer, null: false, default: 0
  end
end
