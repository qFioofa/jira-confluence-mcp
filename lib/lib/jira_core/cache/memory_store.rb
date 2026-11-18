# frozen_string_literal: true

module JiraCore
  module Cache
    class MemoryStore < Store
      def initialize
        @data = {}
        @mutex = Mutex.new
        @hits = 0
        @misses = 0
      end

      def fetch(ns:, logical:, ttl: nil, version: nil)
        key = key_for(ns, logical)
        entry = @mutex.synchronize { @data[key] }
        if entry && entry[:expires_at] > now
          @mutex.synchronize { @hits += 1 }
          return entry[:value]
        end

        value = yield
        write(ns: ns, logical: logical, value: value, ttl: ttl, version: version)
        @mutex.synchronize { @misses += 1 }
        value
      end

      def read(ns:, logical:)
        key = key_for(ns, logical)
        entry = @mutex.synchronize { @data[key] }
        return nil unless entry && entry[:expires_at] > now

        entry[:value]
      end

      def write(ns:, logical:, value:, ttl: nil, version: nil)
        key = key_for(ns, logical)
        @mutex.synchronize do
          @data[key] = { value: value, version: version, expires_at: ttl ? now + ttl.to_i : Float::INFINITY }
        end
        value
      end

      def delete(ns:, logical:)
        @mutex.synchronize { @data.delete(key_for(ns, logical)) }
      end

      def clear(ns: nil, expired: false)
        @mutex.synchronize do
          if ns
            @data.delete_if { |(namespace, _), _| namespace.to_s == ns.to_s }
          elsif expired
            @data.delete_if { |_, entry| entry[:expires_at] <= now }
          else
            @data.clear
          end
        end
        true
      end

      def stats
        { hits: @hits, misses: @misses, source: "memory" }
      end

      def hit_rate
        total = @hits + @misses
        total.positive? ? ((@hits.to_f / total) * 100).round(1) : 0
      end

      def requests
        @hits + @misses
      end

      private

      def key_for(ns, logical)
        [ns.to_s, logical]
      end

      def now
        Time.now.to_f
      end
    end
  end
end
