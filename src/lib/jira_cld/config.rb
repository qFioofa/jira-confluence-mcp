# frozen_string_literal: true

require "etc"

module JiraCld
  class Config
    TRUTHY = %w[1 true yes on].freeze
    FALSY = %w[0 false no off].freeze

    attr_reader :env, :document, :config_path, :project_id, :project, :registry, :config_store

    def self.load(env: ENV, config_path: nil, project_id: :unset, overrides: {})
      path = config_path || env["CONFIG_PATH"] || ConfigStore.default_path(env)
      store = ConfigStore.new(path: path)
      document = store.load
      requested_id = project_id == :unset ? overrides[:project_id] || env["MCP_PROJECT_ID"] : project_id
      new(env: env, document: document, config_path: store.path, project_id: requested_id,
          config_store: store)
    end

    def initialize(env:, document:, config_path:, project_id: nil, config_store: nil)
      @env = env.reject { |_key, value| value.nil? || value.to_s.empty? }
      @document = document
      @config_path = config_path
      @config_store = config_store || ConfigStore.new(path: config_path)
      @registry = ProjectRegistry.new(document, base_dir: data_dir, config_store: @config_store, env: env)
      @project_id = project_id&.to_s
      @project_id = nil if @project_id && @project_id.empty?
      @project = @project_id ? @registry.find(@project_id) : nil
    end

    def reload
      self.class.load(env: env, config_path: config_path, project_id: project_id)
    end

    def projects
      registry.list
    end

    def require_project!
      raise ConfigError, "MCP_PROJECT_ID is required; refusing to start without an explicit project binding" if project_id.nil?

      raise ConfigError, "unknown project #{project_id.inspect}" unless project

      project
    end

    def base_url
      value = env["JIRA_BASE_URL"] || document.dig("connections", "jira", "base_url")
      value&.to_s&.delete_suffix("/")
    end

    def jira_base_url
      base_url || raise(ConfigError, "JIRA_BASE_URL is not configured")
    end

    def deployment
      value = (env["JIRA_DEPLOYMENT"] || document.dig("connections", "jira", "deployment") || "cloud").to_s.downcase
      if %w[cloud dc server data_center].include?(value)
        value.start_with?("dc", "server", "data") ? "dc" : "cloud"
      else
        "cloud"
      end
    end

    def cloud?
      deployment == "cloud"
    end

    def dc?
      deployment == "dc"
    end

    def jira_email
      env["JIRA_EMAIL"] || document.dig("connections", "jira", "email")
    end

    def jira_api_token
      env["JIRA_API_TOKEN"] || resolve_token(document.dig("connections", "jira", "token_ref"))
    end

    def jira_pat
      env["JIRA_PAT"] || resolve_token(document.dig("connections", "jira", "pat_ref"))
    end

    def confluence_base_url
      explicit = env["CONFLUENCE_BASE_URL"] || document.dig("connections", "confluence", "base_url")
      return explicit.to_s.delete_suffix("/") if explicit && !explicit.to_s.empty?

      base = base_url
      return unless base

      base.end_with?("/wiki") ? base : "#{base}/wiki"
    end

    def confluence_pat
      env["CONFLUENCE_PAT"] || resolve_token(document.dig("connections", "confluence", "pat_ref")) ||
        resolve_token(document.dig("connections", "confluence", "token_ref"))
    end

    def confluence_email
      env["CONFLUENCE_EMAIL"] || jira_email
    end

    def confluence_api_token
      env["CONFLUENCE_API_TOKEN"] || jira_api_token
    end

    def space
      project&.spaces&.first || env["CLD_SPACE"] || "CLD"
    end

    def spaces
      project&.spaces&.any? ? project.spaces : [space].compact
    end

    def jira_keys
      project&.jira_keys&.any? ? project.jira_keys : []
    end

    def kb_enabled?
      bool("KB_ENABLED", true) && !spaces.empty?
    end

    def locale
      (env["MCP_LOCALE"] || "ru").to_s
    end

    def output_lang
      (env["OUTPUT_LANG"] || locale).to_s
    end

    def output_char_limit
      int("OUTPUT_CHAR_LIMIT", 24_000)
    end

    def data_dir
      @data_dir ||= File.expand_path(env["DATA_DIR"] || "~/.local/share/jira-cld")
    end

    def db_path
      path = env["DB_PATH"]
      return File.expand_path(path) if path && !path.empty?

      project ? project.cache_db_path : File.join(data_dir, "_unbound", "cache.db")
    end

    def reference_db_path
      File.expand_path(env["REFERENCE_DB_PATH"] || File.join(data_dir, "global", "reference.db"))
    end

    def stats_path
      File.expand_path(env["STATS_PATH"] || File.join(data_dir, "stats.db"))
    end

    def db_auto_migrate?
      bool("DB_AUTO_MIGRATE", true)
    end

    def cache_enabled?
      bool("CACHE_ENABLED", true)
    end

    def cache_l1_bytes
      int("CACHE_L1_BYTES", 8 * 1024 * 1024)
    end

    def cache_max_bytes
      int("CACHE_MAX_BYTES", 16 * 1024 * 1024)
    end

    def cache_max_entry_bytes
      int("CACHE_MAX_ENTRY_BYTES", 256 * 1024)
    end

    def cache_search?
      bool("CACHE_SEARCH", false)
    end

    def cache_stale_grace
      int("CACHE_STALE_GRACE", 600)
    end

    def cache_write_batch
      int("CACHE_WRITE_BATCH", 64)
    end

    def db_cache_size_kb
      int("DB_CACHE_SIZE_KB", 8192)
    end

    def db_mmap_bytes
      int("DB_MMAP_BYTES", 64 * 1024 * 1024)
    end

    def db_page_size
      int("DB_PAGE_SIZE", 8192)
    end

    def db_journal_size_limit
      int("DB_JOURNAL_SIZE_LIMIT", 16 * 1024 * 1024)
    end

    def http_keep_alive?
      bool("HTTP_KEEP_ALIVE", true)
    end

    def http_keep_alive_timeout
      int("HTTP_KEEP_ALIVE_TIMEOUT", 30)
    end

    def http_timeout_ms
      int("HTTP_TIMEOUT_MS", 20_000)
    end

    def query_max_chars
      int("QUERY_MAX_CHARS", 2000)
    end

    def team_show_email?
      return bool("TEAM_SHOW_EMAIL", false) if env.key?("TEAM_SHOW_EMAIL")
      return project.team.fetch("show_email", false) if project

      bool("TEAM_SHOW_EMAIL", false)
    end

    def team_window_days
      int("TEAM_WINDOW_DAYS", 180)
    end

    def log_level
      (env["LOG_LEVEL"] || "info").to_s
    end

    def log_format
      (env["LOG_FORMAT"] || "json").to_s
    end

    def secret_provider
      (env["SECRET_PROVIDER"] || "env").to_s
    end

    def stats_enabled?
      bool("STATS_ENABLED", true)
    end

    def stats_retention_days
      int("STATS_RETENTION_DAYS", 7)
    end

    def mcp_http_host
      (env["MCP_HTTP_HOST"] || "127.0.0.1").to_s
    end

    def mcp_http_port
      int("MCP_HTTP_PORT", 8765)
    end

    def mcp_http_path
      path = (env["MCP_HTTP_PATH"] || "/mcp").to_s
      path = "/#{path}" unless path.start_with?("/")
      path = path.chomp("/") while path.length > 1 && path.end_with?("/")
      path.empty? ? "/mcp" : path
    end

    def mcp_http_url
      host = mcp_http_host == "0.0.0.0" ? "127.0.0.1" : mcp_http_host
      "http://#{host}:#{mcp_http_port}#{mcp_http_path}"
    end

    def mcp_http_stateless?
      bool("MCP_HTTP_STATELESS", false)
    end

    def mcp_http_allowed_hosts
      env["MCP_HTTP_ALLOWED_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def ui_host
      (env["UI_HOST"] || "127.0.0.1").to_s
    end

    def ui_port
      int("UI_PORT", 0)
    end

    def ui_open?
      bool("UI_OPEN", true)
    end

    def ui_locale
      (env["UI_LOCALE"] || locale).to_s
    end

    def ui_theme
      theme = (env["UI_THEME"] || document.dig("ui", "theme") || "system").to_s
      %w[system light dark].include?(theme) ? theme : "system"
    end

    def cross_scope
      document["cross_scope"] || {}
    end

    def to_h(redact: true)
      {
        schema: document["schema"],
        config_path: config_path,
        project_id: project_id,
        jira_base_url: base_url,
        jira_deployment: deployment,
        jira_email: jira_email,
        jira_token: redact ? Secrets.mask(jira_api_token) : jira_api_token,
        jira_pat: redact ? Secrets.mask(jira_pat) : jira_pat,
        confluence_base_url: confluence_base_url,
        confluence_pat: redact ? Secrets.mask(confluence_pat) : confluence_pat,
        spaces: spaces,
        jira_keys: jira_keys,
        locale: locale,
        data_dir: data_dir,
        db_path: db_path,
        reference_db_path: reference_db_path,
        stats_path: stats_path,
        kb_enabled: kb_enabled?,
        cache_enabled: cache_enabled?,
        cache_search: cache_search?,
        deployment: deployment
      }.compact
    end

    private

    def resolve_token(ref)
      return nil if ref.nil? || ref.to_s.empty?

      Secrets.resolve(ref, env: env, provider: secret_provider)
    rescue SecretError
      nil
    end

    def bool(name, default)
      raw = env[name]
      return default if raw.nil?

      value = raw.to_s.downcase
      return true if TRUTHY.include?(value)
      return false if FALSY.include?(value)

      default
    end

    def int(name, default)
      value = env[name]
      return default if value.nil? || value.to_s.empty?

      Integer(value)
    rescue ArgumentError
      default
    end
  end
end
