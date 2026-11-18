# frozen_string_literal: true

module JiraCore
  class Runtime
    attr_accessor :logger
    attr_reader :config, :cache, :reference

    def self.build(config:, cache:, logger: nil, stats_recorder: nil)
      new(config: config, cache: cache, logger: logger, stats_recorder: stats_recorder).tap(&:setup!)
    end

    def initialize(config:, cache:, logger: nil, stats_recorder: nil)
      @config = config
      @cache = cache
      @logger = logger
      @stats_recorder = stats_recorder
      @closed = false
    end

    def setup!
      @reference = Repositories::Reference.new(cache: @cache, logger: @logger)
      self
    end

    def issues
      @issues ||= Repositories::Issues.new(
        config: @config, jira: jira, cache: @cache,
        knowledge_base: knowledge_base, logger: @logger
      )
    end

    def knowledge_base
      @knowledge_base ||= Repositories::KnowledgeBase.new(
        config: @config, confluence: confluence, cache: @cache,
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
      {
        "user" => Serialize::Person.compact(user, show_email: @config.team_show_email?),
        "deployment" => @config.deployment,
        "site" => @config.base_url,
        "space" => @config.space,
        "capabilities" => jira.capabilities.merge("confluence" => confluence.capabilities)
      }
    end

    def cache_stats
      @cache.stats.merge(
        project: @config.project_id,
        hit_rate: @cache.hit_rate,
        requests: @cache.requests
      )
    end

    def record_tool(name, started_at, outcome: "ok", cache: nil)
      return unless @stats_recorder

      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      @stats_recorder.record_tool(tool: name, outcome: outcome, duration_ms: duration, cache: cache)
    end

    def close
      return if @closed

      @closed = true
      @jira_client&.close
      @confluence_client&.close
      @cache&.close
    end
  end
end
