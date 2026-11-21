# frozen_string_literal: true

module JiraCore
  module HTTP
    class Error < StandardError
      attr_reader :status, :headers, :body

      def initialize(message, status: nil, headers: {}, body: nil)
        super(message)
        @status = status
        @headers = headers
        @body = body
      end
    end
  end
end
