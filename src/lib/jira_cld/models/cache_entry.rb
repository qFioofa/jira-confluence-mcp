# frozen_string_literal: true

module JiraCld
  module Models
    class CacheEntry < ApplicationRecord
      self.table_name = "cache_entries"
    end
  end
end
