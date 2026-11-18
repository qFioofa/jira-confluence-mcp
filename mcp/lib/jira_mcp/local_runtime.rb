# frozen_string_literal: true

require "json"

module JiraMcp
  class LocalRuntime
    class ConfigError < JiraCore::ConfigError; end

    class LogSink
      LEVELS = { "debug" => 0, "info" => 1, "warn" => 2, "error" => 3 }.freeze

      def initialize(io: $stderr, level: "info")
        @io = io
        @minimum = LEVELS.fetch(level.to_s.downcase, LEVELS["info"])
        @mutex = Mutex.new
      end

      LEVELS.each do |name, severity|
        define_method(name) do |message = nil, **fields, &block|
          return if severity < @minimum

          write(name, message, fields)
          nil
        end
      end

      private

      def write(level, message, fields)
        payload = { "level" => level, "message" => message }
        payload.merge!(fields.transform_keys(&:to_s)) if fields.any?
        @mutex.synchronize { @io.puts(JSON.generate(payload)) }
      end
    end

    def self.from_env(env = ENV)
      new(env).build
    end

    def initialize(env)
      @env = env
    end

    def build
      validate!
      JiraCore::Runtime.build(
        config: config,
        cache: JiraCore::Cache::MemoryStore.new,
        logger: logger
      )
    end

    def config
      @config ||= JiraCore::Config.new(
        project_id: project_id,
        registry: registry,
        base_url: require_value("JIRA_BASE_URL"),
        jira_base_url: require_value("JIRA_BASE_URL"),
        confluence_base_url: presence("CONFLUENCE_BASE_URL"),
        confluence_web_base_url: presence("CONFLUENCE_BASE_URL"),
        deployment: presence("JIRA_DEPLOYMENT") || "cloud",
        jira_email: presence("JIRA_EMAIL"),
        jira_api_token: presence("JIRA_API_TOKEN"),
        jira_pat: presence("JIRA_PAT"),
        confluence_email: presence("CONFLUENCE_EMAIL") || presence("JIRA_EMAIL"),
        confluence_api_token: presence("CONFLUENCE_API_TOKEN") || presence("JIRA_API_TOKEN"),
        confluence_pat: presence("CONFLUENCE_PAT") || presence("JIRA_PAT"),
        spaces: spaces,
        jira_keys: jira_keys,
        locale: presence("MCP_LOCALE") || "ru",
        output_lang: presence("OUTPUT_LANG"),
        output_char_limit: integer("OUTPUT_CHAR_LIMIT", 24_000),
        query_max_chars: integer("QUERY_MAX_CHARS", 2_000),
        team_show_email: boolean("TEAM_SHOW_EMAIL", false),
        team_window_days: integer("TEAM_WINDOW_DAYS", 180),
        http_timeout_ms: integer("HTTP_TIMEOUT_MS", 20_000),
        http_keep_alive: boolean("HTTP_KEEP_ALIVE", true),
        http_keep_alive_timeout: integer("HTTP_KEEP_ALIVE_TIMEOUT", 30),
        cache_stale_grace: integer("CACHE_STALE_GRACE", 600),
        cache_search: boolean("CACHE_SEARCH", false),
        cache_enabled: boolean("CACHE_ENABLED", true),
        stats_enabled: boolean("STATS_ENABLED", false),
        stats_retention_days: integer("STATS_RETENTION_DAYS", 7),
        log_level: presence("LOG_LEVEL") || "info",
        log_format: "json"
      )
    end

    def logger
      @logger ||= LogSink.new(io: $stderr, level: presence("LOG_LEVEL") || "info")
    end

    private

    def validate!
      require_value("MCP_PROJECT_ID")
      require_value("JIRA_BASE_URL")
      return if presence("JIRA_API_TOKEN") || presence("JIRA_PAT")

      raise ConfigError, "JIRA_API_TOKEN or JIRA_PAT is required"
    end

    def project_id
      require_value("MCP_PROJECT_ID")
    end

    def registry
      JiraCore::ProjectRegistry.new(
        [
          {
            "id" => project_id,
            "name" => presence("MCP_PROJECT_NAME") || project_id,
            "jira_keys" => jira_keys,
            "spaces" => spaces,
            "style" => presence("MCP_PROJECT_STYLE") || "scrum",
            "aliases" => list("MCP_PROJECT_ALIASES"),
            "queries" => { "jql" => {}, "cql" => {} }
          }
        ]
      )
    end

    def jira_keys
      keys = list("JIRA_KEYS")
      keys = list("JIRA_KEY") if keys.empty?
      keys.empty? ? [project_id.upcase] : keys.map(&:upcase)
    end

    def spaces
      list("CLD_SPACE")
    end

    def require_value(key)
      value = presence(key)
      raise ConfigError, "#{key} is required" if value.nil?

      value
    end

    def presence(key)
      value = @env[key].to_s.strip
      value.empty? ? nil : value
    end

    def list(key)
      @env[key].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def integer(key, default)
      raw = presence(key)
      return default if raw.nil?

      Integer(raw)
    rescue ArgumentError
      raise ConfigError, "#{key} must be an integer"
    end

    def boolean(key, default)
      raw = presence(key)
      return default if raw.nil?

      %w[1 true yes on].include?(raw.downcase)
    end
  end
end
