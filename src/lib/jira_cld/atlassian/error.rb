# frozen_string_literal: true

module JiraCld
  module Atlassian
    class Error < StandardError
      attr_reader :code, :status, :hint, :domain

      def initialize(message, code: :request_failed, status: nil, hint: nil, domain: nil)
        super(message)
        @code = code
        @status = status
        @hint = hint
        @domain = domain
      end

      def to_h
        {
          code: code.to_s,
          message: message,
          status: status,
          hint: hint,
          domain: domain
        }.compact
      end
    end
  end
end
