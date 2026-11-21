# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :team
  belongs_to :jira_connection, class_name: "Connection", optional: true
  belongs_to :confluence_connection, class_name: "Connection", optional: true

  has_many :presets, dependent: :destroy
  has_many :cache_strategies, dependent: :destroy
  has_many :mcp_endpoints, dependent: :destroy

  before_validation :normalize_slug
  after_create_commit -> { JiraCache::Provisioner.for_project(self) }

  validates :slug, presence: true, uniqueness: { scope: :team_id },
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true
  validate :connections_belong_to_team

  def jira_keys
    Array(super).map { |key| key.to_s.upcase }
  end

  def spaces
    Array(super).map(&:to_s)
  end

  def jql_presets
    presets.jql
  end

  def cql_presets
    presets.cql
  end

  private

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.tr("_", "-")
  end

  def connections_belong_to_team
    return unless team

    if jira_connection && jira_connection.team_id != team_id
      errors.add(:jira_connection, "must belong to the same team")
    end
    return unless confluence_connection && confluence_connection.team_id != team_id

    errors.add(:confluence_connection, "must belong to the same team")
  end
end
