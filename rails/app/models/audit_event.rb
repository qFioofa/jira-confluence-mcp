# frozen_string_literal: true

class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :team, optional: true

  validates :action, presence: true
end
