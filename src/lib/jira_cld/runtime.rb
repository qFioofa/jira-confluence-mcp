# frozen_string_literal: true

module JiraCld
  class Runtime
    attr_accessor :logger
    attr_reader :config, :reference

    def self.build(config:, logger: nil)
      new(config: config, logger: logger).tap(&:setup!)
    end

    def initialize(config:, logger: nil)
      @config = config
      @logger = logger
      @closed = false
    end

    def setup!
      @logger ||= Logging.build(@config)
      @logger.with_fields = @logger.with_fields.merge(project: @config.project_id) if @logger.respond_to?(:with_fields=)
      I18n.setup(locale: @config.locale)
      @reference = Repositories::Reference.new(config: @config, logger: @logger)
      @stats_writer = Stats::Writer.new(@config, logger: @logger)
      @stats_query = Stats::Query.new(@config)
      self
    end

    def ensure_db!
      return if @db_ready

      DB.setup!(@config)
      @db_ready = true
      @cache = Cache::TieredStore.new(
        config: @config,
        logger: @logger,
        project: @config.project_id,
        site: @config.base_url,
        principal: principal
      )
      @cache.stats_writer = @stats_writer
    end

    def db_ready?
      !!@db_ready
    end

    def cache
      ensure_db!
      @cache
    end

    def stats_writer
      @stats_writer ||= Stats::Writer.new(@config, logger: @logger)
    end

    def stats_query
      ensure_db!
      @stats_query ||= Stats::Query.new(@config)
    end

    def principal
      @config.jira_email || @config.jira_pat&.slice(0, 8) || "local"
    end

    def issues
      @issues ||= Repositories::Issues.new(
        config: @config, jira: jira, cache: cache,
        knowledge_base: knowledge_base, logger: @logger
      )
    end

    def knowledge_base
      @knowledge_base ||= Repositories::KnowledgeBase.new(
        config: @config, confluence: confluence, cache: cache,
        reference: @reference, logger: @logger
      )
    end

    def people
      @people ||= Repositories::People.new(
        config: @config, issues: issues, knowledge_base: knowledge_base, logger: @logger
      )
    end

    def jira
      @jira ||= Atlassian::Jira.new(
        client: jira_client, config: @config, reference: @reference, logger: @logger
      )
    end

    def confluence
      @confluence ||= Atlassian::Confluence.new(
        client: confluence_client, config: @config, reference: @reference, logger: @logger
      )
    end

    def jira_client
      @jira_client ||= HTTP::Client.new(
        base_url: @config.jira_base_url,
        timeout_ms: @config.http_timeout_ms,
        keep_alive: @config.http_keep_alive?,
        keep_alive_timeout: @config.http_keep_alive_timeout,
        logger: @logger
      )
    end

    def confluence_client
      @confluence_client ||= HTTP::Client.new(
        base_url: @config.confluence_base_url || @config.jira_base_url,
        timeout_ms: @config.http_timeout_ms,
        keep_alive: @config.http_keep_alive?,
        keep_alive_timeout: @config.http_keep_alive_timeout,
        logger: @logger
      )
    end

    def whoami
      user = jira.myself
      deployment = @config.deployment
      {
        "user" => Serialize::Person.compact(user, show_email: @config.team_show_email?),
        "deployment" => deployment,
        "site" => @config.base_url,
        "space" => @config.space,
        "capabilities" => jira.capabilities.merge("confluence" => confluence.capabilities)
      }
    end

    def cache_stats
      stats = cache.stats
      hit_rate = cache.total_requests.positive? ? ((cache.total_hits.to_f / cache.total_requests) * 100).round(1) : 0
      stats.merge(
        project: @config.project_id,
        hit_rate: hit_rate,
        requests: cache.total_requests,
        db_path: @config.db_path,
        db_size_bytes: DB.size_bytes
      )
    end

    def record_tool(name, started_at, outcome: "ok", cache: nil)
      return unless stats_writer

      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      stats_writer.record_tool(tool: name, outcome: outcome, duration_ms: duration, cache: cache)
    end

    def close
      return if @closed

      @closed = true
      @stats_writer&.shutdown if @db_ready
      @cache&.checkpoint("TRUNCATE")
      DB.optimize!
      DB.disconnect!
      @jira_client&.close
      @confluence_client&.close
    rescue StandardError => e
      @logger&.warn("runtime shutdown failed", error: e.message)
    end
  end
end
