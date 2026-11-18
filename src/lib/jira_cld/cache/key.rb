# frozen_string_literal: true

require "digest"
require "json"

module JiraCld
  module Cache
    module Key
      module_function

      def build(project:, site:, principal:, ns:, logical:)
        digest = Digest::SHA256.hexdigest(canonical(logical))
        "v1:#{sanitize(project)}:#{sanitize(site)}:#{sanitize(principal)}:#{sanitize(ns)}:#{digest}"
      end

      def canonical(logical)
        case logical
        when Hash
          JSON.generate(deep_sort(logical))
        when Array
          JSON.generate(logical.map { |item| item.is_a?(Hash) ? deep_sort(item) : item })
        else
          logical.to_s
        end
      end

      def deep_sort(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, deep_sort(value[key])] }
        when Array
          value.map { |item| deep_sort(item) }
        else
          value
        end
      end

      def namespace_from(key)
        key.to_s.split(":", 6)[4]
      end

      def sanitize(value)
        text = value.to_s.gsub(/[^a-zA-Z0-9_.-]/, "_")
        text.empty? ? "default" : text[0, 80]
      end
    end
  end
end
