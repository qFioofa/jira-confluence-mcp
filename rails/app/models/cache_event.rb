# frozen_string_literal: true

class CacheEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :project, optional: true

  validates :namespace, presence: true
end
