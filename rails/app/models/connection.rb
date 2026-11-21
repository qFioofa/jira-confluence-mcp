# frozen_string_literal: true

class Connection < ApplicationRecord
  belongs_to :team
  has_many :user_credentials, dependent: :destroy
  has_many :projects_as_jira, class_name: "Project", foreign_key: :jira_connection_id, dependent: :nullify
  has_many :projects_as_confluence, class_name: "Project", foreign_key: :confluence_connection_id, dependent: :nullify

  enum :provider, { jira: "jira", confluence: "confluence" }
  enum :deployment, { cloud: "cloud", dc: "dc" }
  enum :status, { unknown: "unknown", ok: "ok", error: "error" }

  before_validation :normalize_base_url

  validates :name, presence: true
  validates :base_url, presence: true
  validates :base_url, uniqueness: { scope: %i[team_id provider] }

  def capabilities
    settings.fetch("capabilities", {})
  end

  def jira?
    provider == "jira"
  end

  def confluence?
    provider == "confluence"
  end

  private

  def normalize_base_url
    self.base_url = base_url.to_s.strip.delete_suffix("/")
  end
end
