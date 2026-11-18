# frozen_string_literal: true

module JiraCld
  module Atlassian
    class ForbiddenError < Error
      def initialize(message = "access forbidden", **)
        super(message, code: :forbidden, **)
      end
    end
  end
end
