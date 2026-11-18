# frozen_string_literal: true

require "base64"
require "json"

module JiraCld
  module Atlassian
    module Cursor
      module_function

      def encode(payload)
        data = { v: 1 }.merge(payload)
        Base64.urlsafe_encode64(JSON.generate(data), padding: false)
      end

      def decode(value)
        return {} if value.nil? || value.to_s.empty?
        return nil unless value.is_a?(String)

        padded = value + ("=" * ((4 - (value.length % 4)) % 4))
        data = JSON.parse(Base64.urlsafe_decode64(padded))
        return nil unless data.is_a?(Hash) && data["v"].to_i == 1

        data.transform_keys(&:to_sym)
      rescue ArgumentError, JSON::ParserError
        nil
      end
    end
  end
end
