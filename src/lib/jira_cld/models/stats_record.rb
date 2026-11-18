# frozen_string_literal: true

module JiraCld
  module Models
    class StatsRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
