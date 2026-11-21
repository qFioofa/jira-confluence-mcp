# frozen_string_literal: true

class CacheStrategy < ApplicationRecord
  belongs_to :project
  belongs_to :user, optional: true
  belongs_to :connection, optional: true

  validates :namespace, presence: true
  validates :ttl_seconds, numericality: { greater_than: 0 }
  validates :stale_grace_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :namespace, uniqueness: { scope: %i[project_id user_id connection_id] }

  after_commit :bump_project_generation, on: :update

  private

  def bump_project_generation
    return unless saved_change_to_ttl_seconds? || saved_change_to_stale_grace_seconds? || saved_change_to_enabled?

    project.increment!(:cache_generation)
  end
end
