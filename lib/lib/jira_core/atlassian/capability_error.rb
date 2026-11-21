# frozen_string_literal: true

module JiraCore
  module Atlassian
    class CapabilityError < Error
      def initialize(message = "deployment capability is unavailable", **)
        super(message, code: :deployment_capability, **)
      end
    end
  end
end
