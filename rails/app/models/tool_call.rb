# frozen_string_literal: true

class ToolCall < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :project, optional: true
  belongs_to :connection, optional: true

  validates :tool, presence: true
  validates :outcome, presence: true
end
