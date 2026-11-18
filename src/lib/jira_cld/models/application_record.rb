# frozen_string_literal: true

require "active_record"

module JiraCld
  module Models
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
