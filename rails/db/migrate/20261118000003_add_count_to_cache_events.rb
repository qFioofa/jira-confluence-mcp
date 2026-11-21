# frozen_string_literal: true

class AddCountToCacheEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :cache_events, :count, :integer, null: false, default: 1
  end
end
