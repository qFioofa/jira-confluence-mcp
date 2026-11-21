# frozen_string_literal: true

class Membership < ApplicationRecord
  belongs_to :team
  belongs_to :user

  enum :role, { viewer: "viewer", member: "member", admin: "admin" }, default: :member

  validates :user_id, uniqueness: { scope: :team_id }
end
