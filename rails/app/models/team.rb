# frozen_string_literal: true

class Team < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :connections, dependent: :destroy
  has_many :projects, dependent: :destroy

  before_validation :normalize_slug

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true

  private

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.tr("_", "-")
  end
end
