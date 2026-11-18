# frozen_string_literal: true

module JiraCache
  class RailsStore < JiraCore::Cache::Store
    attr_reader :resolver, :key_builder

    def initialize(cache:, user:, project:, connections:, resolver:, logger: nil)
      @cache = cache
      @user = user
      @project = project
      @connections = Array(connections).compact
      @resolver = resolver
      @key_builder = KeyBuilder.new(user: user, project: project, connections: @connections)
      @logger = logger
      @counters = Hash.new(0)
      @pending_events = Hash.new(0)
      @mutex = Mutex.new
    end

    def fetch(ns:, logical:, ttl: nil, version: nil)
      ns = ns.to_s
      return yield unless @resolver.enabled?(ns)

      key = @key_builder.key(ns, logical)
      ttl ||= @resolver.ttl(ns)
      now = now_s
      envelope = @cache.read(key)

      if envelope
        fresh_until = value_from(envelope, :fresh_until).to_i
        if fresh_until > now
          count(:hit, ns)
          return value_from(envelope, :value)
        end

        stale_until = value_from(envelope, :stale_until).to_i
        if @resolver.stale?(ns) && stale_until > now
          begin
            value = yield
            write(ns: ns, logical: logical, value: value, ttl: ttl, version: version)
            count(:revalidated, ns)
            return value
          rescue StandardError
            count(:stale, ns)
            return value_from(envelope, :value)
          end
        end
      end

      value = yield
      write(ns: ns, logical: logical, value: value, ttl: ttl, version: version)
      count(:miss, ns)
      value
    end

    def read(ns:, logical:)
      envelope = @cache.read(@key_builder.key(ns.to_s, logical))
      envelope ? value_from(envelope, :value) : nil
    end

    def write(ns:, logical:, value:, ttl: nil, version: nil)
      ns = ns.to_s
      return value unless @resolver.enabled?(ns)

      ttl ||= @resolver.ttl(ns)
      return value if ttl.to_i <= 0

      now = now_s
      fresh_until = now + ttl.to_i
      grace = @resolver.stale_grace(ns).to_i
      stale_until = fresh_until + grace
      envelope = {
        value: value,
        fresh_until: fresh_until,
        stale_until: stale_until,
        version: version,
        namespace: ns
      }
      @cache.write(@key_builder.key(ns, logical), envelope, expires_in: [stale_until - now, 1].max)
      value
    rescue StandardError => e
      @logger&.warn("cache write failed", error: e.message)
      value
    end

    def delete(ns:, logical:)
      @cache.delete(@key_builder.key(ns.to_s, logical))
    end

    def clear(ns: nil, expired: false)
      @project.increment!(:cache_generation)
      true
    rescue StandardError => e
      @logger&.warn("cache clear failed", error: e.message)
      false
    end

    def stats
      {
        hits: hits_count + pending_count(:hit),
        misses: misses_count + pending_count(:miss),
        revalidated: @counters[:revalidated] + pending_count(:revalidated),
        stale: @counters[:stale] + pending_count(:stale),
        source: "rails",
        backend: @cache.class.name
      }
    end

    def hit_rate
      total = hits_count + misses_count
      total.positive? ? ((hits_count.to_f / total) * 100).round(1) : 0
    end

    def requests
      hits_count + misses_count + pending_count(:hit) + pending_count(:miss)
    end

    def flush_stats!
      return true unless defined?(::CacheEvent)

      pending = @mutex.synchronize do
        events = @pending_events.dup
        @pending_events.clear
        events
      end
      return true if pending.empty?

      now = Time.current
      pending.each do |(namespace, source), count|
        ::CacheEvent.create!(
          user: @user,
          project: @project,
          namespace: namespace,
          hit: %i[hit revalidated].include?(source),
          source: source,
          count: count,
          created_at: now
        )
      end
      true
    rescue StandardError => e
      @logger&.warn("cache event flush failed", error: e.message)
      false
    end

    def close
      flush_stats!
      nil
    end

    private

    def count(name, namespace)
      @mutex.synchronize do
        @counters[name] += 1
        @pending_events[[namespace.to_s, name.to_s]] += 1
      end
    end

    def pending_count(name)
      @mutex.synchronize do
        @pending_events.sum { |(_, source), count| source == name.to_s ? count : 0 }
      end
    end

    def hits_count
      persisted_count(hit: true)
    end

    def misses_count
      persisted_count(hit: false)
    end

    def persisted_count(hit:)
      return @counters[hit ? :hit : :miss] unless defined?(::CacheEvent)

      ::CacheEvent.where(user: @user, project: @project, hit: hit).sum(:count)
    rescue StandardError
      @counters[hit ? :hit : :miss]
    end

    def value_from(envelope, key)
      return unless envelope.respond_to?(:[])

      envelope[key] || envelope[key.to_s]
    end

    def now_s
      Time.now.to_i
    end
  end
end
