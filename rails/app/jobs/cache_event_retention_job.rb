# frozen_string_literal: true

class CacheEventRetentionJob < ApplicationJob
  queue_as :default

  def perform(retention_days: 7)
    threshold = retention_days.to_i.days.ago
    CacheEvent.where("created_at < ?", threshold).delete_all
    ToolCall.where("created_at < ?", threshold).delete_all
  end
end
