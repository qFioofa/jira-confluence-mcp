# frozen_string_literal: true

module JiraCore
  module Atlassian
    class RateLimitedError < Error
      def initialize(message = "rate limited by Atlassian", **)
        super(message, code: :rate_limited, **)
      end
    end
  end
end
