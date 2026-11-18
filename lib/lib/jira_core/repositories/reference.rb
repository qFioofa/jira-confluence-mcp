# frozen_string_literal: true

module JiraCore
  module Repositories
    class Reference
      TTL = 24 * 60 * 60

      def initialize(cache:, logger: nil)
        @cache = cache
        @logger = logger
      end

      def get(ns, key)
        @cache.read(ns: namespace(ns), logical: key.to_s)
      rescue StandardError => e
        @logger&.warn("reference read failed", error: e.message)
        nil
      end

      def put(ns, key, value, ttl: TTL, version: nil)
        @cache.write(ns: namespace(ns), logical: key.to_s, value: value, ttl: ttl, version: version)
        value
      rescue StandardError => e
        @logger&.warn("reference write failed", error: e.message)
        value
      end

      def fetch(ns, key, ttl: TTL, &block)
        @cache.fetch(ns: namespace(ns), logical: key.to_s, ttl: ttl, &block)
      end

      def clear
        @cache.clear(ns: "reference")
      end

      private

      def namespace(ns)
        "reference_#{ns}"
      end
    end
  end
end
