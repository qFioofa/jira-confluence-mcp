# frozen_string_literal: true

module JiraCore
  module Cache
    class Store
      def fetch(ns:, logical:, ttl: nil, version: nil, &block)
        raise NotImplementedError
      end

      def read(ns:, logical:)
        raise NotImplementedError
      end

      def write(ns:, logical:, value:, ttl: nil, version: nil)
        raise NotImplementedError
      end

      def delete(ns:, logical:)
        raise NotImplementedError
      end

      def clear(ns: nil, expired: false)
        raise NotImplementedError
      end

      def stats
        {}
      end

      def hit_rate
        0.0
      end

      def requests
        0
      end

      def close
        nil
      end
    end
  end
end
