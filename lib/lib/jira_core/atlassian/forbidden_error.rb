# frozen_string_literal: true

module JiraCore
  module Atlassian
    class ForbiddenError < Error
      def initialize(message = "access forbidden", **)
        super(message, code: :forbidden, **)
      end
    end
  end
end
