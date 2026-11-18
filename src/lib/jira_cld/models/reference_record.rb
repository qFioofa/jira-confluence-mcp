# frozen_string_literal: true

module JiraCld
  module Models
    class ReferenceRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
