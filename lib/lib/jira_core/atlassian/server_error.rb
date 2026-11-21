# frozen_string_literal: true

module JiraCore
  module Atlassian
    class ServerError < Error
      def initialize(message = "Atlassian server error", **)
        super(message, code: :server_error, **)
      end
    end
  end
end
