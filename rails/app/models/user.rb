# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_many :memberships, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :user_credentials, dependent: :destroy
  has_many :mcp_endpoints, dependent: :destroy

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true, allow_blank: true

  def membership_for(team)
    memberships.find_by(team: team)
  end

  def member_of?(team)
    memberships.exists?(team: team)
  end

  def admin_of?(team)
    memberships.where(team: team).exists?(role: "admin")
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
