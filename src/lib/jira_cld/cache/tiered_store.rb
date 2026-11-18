# frozen_string_literal: true

require "active_support/cache/memory_store"

module JiraCld
  module Cache
    class TieredStore
      Result = Struct.new(:value, :stale, :source, :version, keyword_init: true)

      attr_reader :policy, :project, :site, :principal
      attr_accessor :stats_writer

      def initialize(config:, policy: nil, logger: nil, project: nil, site: nil, principal: "local")
        @config = config
        @policy = policy || Policy.new(config)
        @logger = logger
        @project = project || config.project_id || "unbound"
        @site = site || config.base_url || "local"
        @principal = principal || "local"
        @l1 = ActiveSupport::Cache::MemoryStore.new(size: config.cache_l1_bytes)
        @l2 = DatabaseStore.new(
          max_bytes: config.cache_max_bytes,
          stale_grace: config.cache_stale_grace,
          max_entry_bytes: config.cache_max_entry_bytes,
          logger: logger
        )
        @counters = Hash.new(0)
        @counters_lock = Mutex.new
      end

      def key_for(ns:, logical:)
        Key.build(project: project, site: site, principal: principal, ns: ns, logical: logical)
      end

      def fetch(ns:, logical:, ttl: nil, version: nil, allow_stale: nil, &)
        fetch_with_meta(ns: ns, logical: logical, ttl: ttl, version: version, allow_stale: allow_stale, &).value
      end

      def fetch_with_meta(ns:, logical:, ttl: nil, version: nil, allow_stale: nil, &block)
        ns = ns.to_s
        return Result.new(value: yield, stale: false, source: :bypass, version: version) unless @policy.enabled_for?(ns)

        key = key_for(ns: ns, logical: logical)
        ttl ||= @policy.ttl(ns)
        grace = @policy.stale_grace(ns)
        allow_stale = @policy.stale?(ns) if allow_stale.nil?

        if (cached = @l1.read(key))
          count(:hit_l1, ns)
          return Result.new(value: cached, stale: false, source: :l1, version: version)
        end

        record = @l2.read_record(key)
        if record && !record.stale?
          @l1.write(key, record.value, expires_in: ttl)
          count(:hit_l2, ns)
          return Result.new(value: record.value, stale: false, source: :l2, version: record.version || version)
        end

        if record&.stale? && allow_stale
          begin
            value = yield
            write(ns: ns, logical: logical, value: value, ttl: ttl, version: version, stale_grace: grace)
            count(:revalidated, ns)
            return Result.new(value: value, stale: false, source: :revalidated, version: version)
          rescue StandardError
            count(:stale, ns)
            return Result.new(value: record.value, stale: true, source: :stale, version: record.version || version)
          end
        end

        value = yield
        write(ns: ns, logical: logical, value: value, ttl: ttl, version: version, stale_grace: grace)
        count(:miss, ns)
        Result.new(value: value, stale: false, source: :miss, version: version)
      end

      def write(ns:, logical:, value:, ttl: nil, version: nil, stale_grace: nil)
        return value unless @policy.enabled_for?(ns.to_s)

        key = key_for(ns: ns, logical: logical)
        ttl ||= @policy.ttl(ns)
        @l1.write(key, value, expires_in: ttl)
        @l2.write_record(
          key, value, ns: ns, ttl: ttl, version: version,
                      stale_grace: stale_grace.nil? ? @policy.stale_grace(ns) : stale_grace
        )
        value
      end

      def read(ns:, logical:)
        key = key_for(ns: ns, logical: logical)
        @l1.read(key) || @l2.read_record(key)&.value
      end

      def delete(ns:, logical:)
        key = key_for(ns: ns, logical: logical)
        @l1.delete(key)
        @l2.delete_entry(key)
      end

      def clear(ns: nil, expired: false)
        @l1.clear
        @l2.clear(ns: ns, expired: expired)
      end

      def stats
        base = {
          hits: @counters[:hit_l1] + @counters[:hit_l2],
          hit_l1: @counters[:hit_l1],
          hit_l2: @counters[:hit_l2],
          misses: @counters[:miss],
          revalidated: @counters[:revalidated],
          stale: @counters[:stale]
        }
        base.merge(@l2.stats)
      end

      def checkpoint(mode = "PASSIVE")
        @l2.checkpoint(mode)
      end

      def total_hits
        @counters[:hit_l1] + @counters[:hit_l2]
      end

      def total_requests
        total_hits + @counters[:miss] + @counters[:revalidated] + @counters[:stale]
      end

      private

      def count(name, namespace = nil)
        @counters_lock.synchronize { @counters[name] += 1 }
        return unless @stats_writer
        return unless %i[hit_l1 hit_l2 miss stale revalidated].include?(name)

        @stats_writer.record_cache(
          hit: name.to_s.start_with?("hit"),
          namespace: namespace,
          source: name.to_s
        )
      end
    end
  end
end
