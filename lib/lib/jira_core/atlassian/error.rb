# frozen_string_literal: true

module JiraCore
  module Atlassian
    class Error < StandardError
      attr_reader :code, :status, :hint, :domain, :details

      def initialize(message, code: :request_failed, status: nil, hint: nil, domain: nil, details: nil)
        super(message)
        @code = code
        @status = status
        @hint = hint
        @domain = domain
        @details = details
      end

      def to_h
        {
          code: code.to_s,
          message: message,
          status: status,
          hint: hint,
          domain: domain,
          details: details
        }.compact
      end
    end
  end
end
