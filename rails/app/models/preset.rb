# frozen_string_literal: true

class Preset < ApplicationRecord
  belongs_to :project

  enum :kind, { jql: "jql", cql: "cql" }

  validates :key, presence: true, uniqueness: { scope: %i[project_id kind] }
  validates :label, presence: true
  validates :query, presence: true, allow_blank: true
  validates :default_limit, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
end
