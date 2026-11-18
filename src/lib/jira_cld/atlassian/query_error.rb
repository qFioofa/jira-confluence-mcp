# frozen_string_literal: true

module JiraCld
  module Atlassian
    class QueryError < Error
      attr_reader :query_code

      def initialize(message, query_code: :query_invalid, **)
        super(message, code: query_code, **)
        @query_code = query_code
      end
    end
  end
end
