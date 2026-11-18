# frozen_string_literal: true

module JiraCld
  module Atlassian
    class NotFoundError < Error
      def initialize(message = "not found", **)
        super(message, code: :not_found, **)
      end
    end
  end
end
