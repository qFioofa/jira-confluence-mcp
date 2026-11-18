# frozen_string_literal: true

module JiraCld
  module Cache
    class Policy
      DEFAULTS = {
        "identity" => { ttl: 3600, stale: false },
        "reference" => { ttl: 21_600, stale: true },
        "issue" => { ttl: 60, stale: false },
        "comments" => { ttl: 120, stale: false },
        "changelog" => { ttl: 120, stale: false },
        "attachments" => { ttl: 300, stale: false },
        "page_meta" => { ttl: 600, stale: true },
        "page" => { ttl: 600, stale: true },
        "children" => { ttl: 300, stale: true },
        "search" => { ttl: 45, stale: false },
        "sprint" => { ttl: 300, stale: false },
        "board" => { ttl: 600, stale: false },
        "negative" => { ttl: 30, stale: false }
      }.freeze

      def initialize(config)
        @config = config
      end

      def for(name)
        DEFAULTS[name.to_s] || { ttl: 60, stale: false }
      end

      def ttl(name, override = nil)
        override || self.for(name)[:ttl]
      end

      def stale?(name)
        self.for(name)[:stale]
      end

      def stale_grace(name)
        stale?(name) ? @config.cache_stale_grace : 0
      end

      def enabled_for?(name)
        return false unless @config.cache_enabled?
        return @config.cache_search? if name.to_s == "search"

        true
      end
    end
  end
end
