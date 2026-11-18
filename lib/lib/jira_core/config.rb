# frozen_string_literal: true

module JiraCore
  class Config
    attr_reader :project_id, :registry, :spaces, :jira_keys

    def initialize(
      project_id:,
      registry:,
      base_url:,
      jira_base_url: nil,
      confluence_base_url: nil,
      deployment: "cloud",
      jira_email: nil,
      jira_api_token: nil,
      jira_pat: nil,
      jira_oauth_token: nil,
      confluence_email: nil,
      confluence_api_token: nil,
      confluence_pat: nil,
      confluence_oauth_token: nil,
      confluence_web_base_url: nil,
      spaces: [],
      jira_keys: [],
      locale: "ru",
      output_lang: nil,
      output_char_limit: 24_000,
      query_max_chars: 2_000,
      team_show_email: false,
      team_window_days: 180,
      http_timeout_ms: 20_000,
      http_keep_alive: true,
      http_keep_alive_timeout: 30,
      cache_stale_grace: 600,
      cache_max_bytes: 16 * 1024 * 1024,
      cache_max_entry_bytes: 256 * 1024,
      cache_l1_bytes: 8 * 1024 * 1024,
      cache_search: false,
      cache_enabled: true,
      cache_write_batch: 64,
      stats_enabled: true,
      stats_retention_days: 7,
      log_level: "info",
      log_format: "json"
    )
      @project_id = project_id&.to_s
      @project_id = nil if @project_id&.empty?
      @registry = registry
      @base_url = base_url&.to_s&.delete_suffix("/")
      @jira_base_url = jira_base_url&.to_s&.delete_suffix("/")
      @confluence_base_url = confluence_base_url&.to_s&.delete_suffix("/")
      @deployment = normalize_deployment(deployment)
      @jira_email = jira_email
      @jira_api_token = jira_api_token
      @jira_pat = jira_pat
      @jira_oauth_token = jira_oauth_token
      @confluence_email = confluence_email
      @confluence_api_token = confluence_api_token
      @confluence_pat = confluence_pat
      @confluence_oauth_token = confluence_oauth_token
      @confluence_web_base_url = confluence_web_base_url&.to_s&.delete_suffix("/")
      @spaces = Array(spaces).map(&:to_s)
      @jira_keys = Array(jira_keys).map { |key| key.to_s.upcase }
      @locale = locale.to_s
      @output_lang = (output_lang || locale).to_s
      @output_char_limit = output_char_limit
      @query_max_chars = query_max_chars
      @team_show_email = team_show_email
      @team_window_days = team_window_days
      @http_timeout_ms = http_timeout_ms
      @http_keep_alive = http_keep_alive
      @http_keep_alive_timeout = http_keep_alive_timeout
      @cache_stale_grace = cache_stale_grace
      @cache_max_bytes = cache_max_bytes
      @cache_max_entry_bytes = cache_max_entry_bytes
      @cache_l1_bytes = cache_l1_bytes
      @cache_search = cache_search
      @cache_enabled = cache_enabled
      @cache_write_batch = cache_write_batch
      @stats_enabled = stats_enabled
      @stats_retention_days = stats_retention_days
      @log_level = log_level
      @log_format = log_format
    end

    def base_url
      @base_url
    end

    def jira_base_url
      @jira_base_url || base_url || raise(ConfigError, "Jira base URL is not configured")
    end

    def confluence_base_url
      return @confluence_base_url if @confluence_base_url

      base = base_url
      return unless base

      base.end_with?("/wiki") ? base : "#{base}/wiki"
    end

    def deployment
      @deployment
    end

    def cloud?
      deployment == "cloud"
    end

    def dc?
      deployment == "dc"
    end

    attr_reader :jira_email, :jira_api_token, :jira_pat, :jira_oauth_token,
                :confluence_email, :confluence_api_token, :confluence_pat, :confluence_oauth_token

    def space
      spaces.first
    end

    def kb_enabled?
      !spaces.empty?
    end

    def confluence_web_base_url
      @confluence_web_base_url || confluence_base_url
    end

    attr_reader :locale, :output_lang, :output_char_limit, :query_max_chars,
                :team_window_days, :http_timeout_ms, :http_keep_alive_timeout,
                :cache_stale_grace, :cache_max_bytes, :cache_max_entry_bytes,
                :cache_l1_bytes, :cache_write_batch, :stats_retention_days,
                :log_level, :log_format

    def team_show_email?
      !!@team_show_email
    end

    def http_keep_alive?
      !!@http_keep_alive
    end

    def cache_search?
      !!@cache_search
    end

    def cache_enabled?
      !!@cache_enabled
    end

    def stats_enabled?
      !!@stats_enabled
    end

    def project
      registry&.find(project_id)
    end

    def projects
      registry&.list || []
    end

    def require_project!
      raise ConfigError, "MCP_PROJECT_ID is required; refusing to start without an explicit project binding" if project_id.nil?
      raise ConfigError, "unknown project #{project_id.inspect}" unless project

      project
    end

    private

    def normalize_deployment(value)
      normalized = value.to_s.downcase
      %w[dc server data_center].include?(normalized) ? "dc" : "cloud"
    end
  end
end
