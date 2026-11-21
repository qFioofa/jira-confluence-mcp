# frozen_string_literal: true

require "digest"

class McpEndpoint < ApplicationRecord
  belongs_to :user
  belongs_to :project

  attr_reader :token

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validate :user_belongs_to_project_team

  scope :active, -> { where(revoked_at: nil) }

  def self.issue!(user:, project:, name:)
    token = SecureRandom.urlsafe_base64(32)
    endpoint = create!(
      user: user,
      project: project,
      name: name,
      token_digest: digest(token),
      token_prefix: token.first(8)
    )
    endpoint.instance_variable_set(:@token, token)
    endpoint
  end

  def self.authenticate(token)
    return if token.blank?

    active.find_by(token_digest: digest(token))
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def touch_usage!
    return if last_used_at.present? && last_used_at > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def user_belongs_to_project_team
    return unless user && project

    errors.add(:user, "must belong to the project team") unless user.teams.exists?(id: project.team_id)
  end
end
