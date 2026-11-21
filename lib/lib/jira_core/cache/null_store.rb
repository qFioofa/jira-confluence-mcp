# frozen_string_literal: true

module JiraCore
  module Cache
    class NullStore < Store
      def fetch(ns:, logical:, ttl: nil, version: nil)
        yield
      end

      def read(ns:, logical:)
        nil
      end

      def write(ns:, logical:, value:, ttl: nil, version: nil)
        value
      end

      def delete(ns:, logical:)
        nil
      end

      def clear(ns: nil, expired: false)
        true
      end

      def stats
        { hits: 0, misses: 0, revalidated: 0, stale: 0, source: "null" }
      end
    end
  end
end
