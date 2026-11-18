# frozen_string_literal: true

class RuntimeBuilder
  class MissingCredential < StandardError
    attr_reader :connection, :project

    def initialize(connection:, project:)
      @connection = connection
      @project = project
      super("No credential for #{connection.provider} connection #{connection.name.inspect}")
    end
  end

  def initialize(endpoint, cache: Rails.cache, logger: Rails.logger)
    @endpoint = endpoint
    @cache = cache
    @logger = StructuredLogger.new(logger)
  end

  def build
    project = @endpoint.project
    jira_connection = project.jira_connection
    confluence_connection = project.confluence_connection

    raise MissingCredential.new(connection: jira_connection, project: project) if jira_connection.nil?

    jira_credential = credential_for(jira_connection)
    raise MissingCredential.new(connection: jira_connection, project: project) unless jira_credential

    confluence_credential = confluence_connection ? credential_for(confluence_connection) : nil
    if confluence_connection && confluence_credential.nil?
      raise MissingCredential.new(connection: confluence_connection, project: project)
    end

    jira_token = jira_credential.secret
    confluence_token = confluence_credential ? confluence_credential.secret : jira_token
    jira_api_base = jira_connection.base_url
    confluence_api_base = confluence_connection&.base_url

    connections = [jira_connection, confluence_connection].compact
    resolver = JiraCache::StrategyResolver.new(project: project, user: @endpoint.user, connections: connections)
    cache = JiraCache::RailsStore.new(
      cache: @cache,
      user: @endpoint.user,
      project: project,
      connections: connections,
      resolver: resolver,
      logger: @logger
    )

    JiraCore::Runtime.build(
      config: build_config(
        project, jira_connection, confluence_connection,
        jira_credential, confluence_credential,
        jira_token: jira_token,
        confluence_token: confluence_token,
        jira_api_base: jira_api_base,
        confluence_api_base: confluence_api_base
      ),
      cache: cache,
      logger: @logger,
      stats_recorder: RailsStatsRecorder.new(
        user: @endpoint.user,
        project: project,
        connection: jira_connection,
        logger: @logger
      )
    )
  end

  private

  def credential_for(connection)
    UserCredential.find_by(user: @endpoint.user, connection: connection)
  end

  def build_config(project, jira_connection, confluence_connection, jira_credential, confluence_credential,
                   jira_token:, confluence_token:, jira_api_base:, confluence_api_base:)
    jira_pat = jira_credential.pat? ? jira_token : nil
    jira_api_token = jira_credential.api_token? ? jira_token : nil

    confluence_pat = if confluence_credential
                       confluence_credential.pat? ? confluence_token : nil
                     else
                       jira_pat
                     end
    confluence_api_token = if confluence_credential
                             confluence_credential.api_token? ? confluence_token : nil
                           else
                             jira_api_token
                           end

    JiraCore::Config.new(
      project_id: project.slug,
      registry: build_registry(project.team),
      base_url: jira_connection.base_url,
      jira_base_url: jira_api_base,
      confluence_base_url: confluence_api_base,
      confluence_web_base_url: confluence_connection&.base_url,
      deployment: jira_connection.deployment,
      jira_email: jira_credential.email,
      jira_api_token: jira_api_token,
      jira_pat: jira_pat,
      confluence_email: confluence_credential&.email || jira_credential.email,
      confluence_api_token: confluence_api_token,
      confluence_pat: confluence_pat,
      spaces: project.spaces,
      jira_keys: project.jira_keys,
      locale: project.settings.fetch("locale", "ru"),
      output_lang: project.settings["output_lang"],
      output_char_limit: project.settings.fetch("output_char_limit", 24_000),
      query_max_chars: project.settings.fetch("query_max_chars", 2_000),
      team_show_email: project.settings.fetch("team_show_email", false),
      team_window_days: project.settings.fetch("team_window_days", 180),
      http_timeout_ms: project.settings.fetch("http_timeout_ms", 20_000),
      http_keep_alive: project.settings.fetch("http_keep_alive", true),
      http_keep_alive_timeout: project.settings.fetch("http_keep_alive_timeout", 30),
      cache_stale_grace: project.settings.fetch("cache_stale_grace", 600),
      cache_search: project.settings.fetch("cache_search", false),
      cache_enabled: project.settings.fetch("cache_enabled", true),
      stats_enabled: project.settings.fetch("stats_enabled", true),
      stats_retention_days: project.settings.fetch("stats_retention_days", 7)
    )
  end

  def build_registry(team)
    projects = team.projects.includes(:presets).order(:name).map do |project|
      {
        "id" => project.slug,
        "name" => project.name,
        "jira_keys" => project.jira_keys,
        "spaces" => project.spaces,
        "style" => project.style,
        "aliases" => project.settings.fetch("aliases", []),
        "related_scopes" => project.settings.fetch("related_scopes", []),
        "team" => project.settings.fetch("team", {}),
        "queries" => {
          "jql" => presets_for(project, "jql"),
          "cql" => presets_for(project, "cql")
        }
      }
    end
    JiraCore::ProjectRegistry.new(projects)
  end

  def presets_for(project, kind)
    project.presets.where(kind: kind).each_with_object({}) do |preset, memo|
      memo[preset.key] = {
        "label" => preset.label,
        "query" => preset.query,
        "order_by" => preset.order_by,
        "default_limit" => preset.default_limit,
        "description" => preset.description
      }.compact
    end
  end
end
