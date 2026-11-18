# frozen_string_literal: true

module JiraCld
  module Atlassian
    class AuthError < Error
      def initialize(message = "authentication failed", **)
        super(message, code: :auth_failed, **)
      end
    end
  end
end
