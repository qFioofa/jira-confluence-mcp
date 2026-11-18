# frozen_string_literal: true

module JiraCore
  module Atlassian
    class NotFoundError < Error
      def initialize(message = "not found", **)
        super(message, code: :not_found, **)
      end
    end
  end
end
