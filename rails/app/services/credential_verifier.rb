# frozen_string_literal: true

class CredentialVerifier
  Result = Struct.new(:ok?, :message, keyword_init: true)

  def initialize(credential, logger: StructuredLogger.new(Rails.logger))
    @credential = credential
    @connection = credential.connection
    @logger = logger
  end

  def call
    data = @connection.jira? ? verify_jira : verify_confluence
    @credential.update!(status: "ok", last_verified_at: Time.current)
    @connection.update_columns(status: "ok", last_checked_at: Time.current)
    Result.new(ok?: true, message: display_name(data))
  rescue StandardError => e
    @logger&.warn("credential verification failed", error: e.message, class: e.class.name)
    @credential.update_columns(status: "error", last_verified_at: Time.current)
    @connection.update_columns(status: "error", last_checked_at: Time.current)
    Result.new(ok?: false, message: e.message)
  end

  private

  def verify_jira
    build_jira.myself
  end

  def verify_confluence
    build_confluence.space(space_key)
  end

  def build_jira
    JiraCore::Atlassian::Jira.new(
      client: client,
      config: config,
      reference: reference,
      logger: @logger
    )
  end

  def build_confluence
    JiraCore::Atlassian::Confluence.new(
      client: client,
      config: config,
      reference: reference,
      logger: @logger
    )
  end

  def client
    JiraCore::HTTP::Client.new(
      base_url: @connection.base_url,
      timeout_ms: 20_000,
      logger: @logger
    )
  end

  def reference
    JiraCore::Repositories::Reference.new(cache: JiraCore::Cache::NullStore.new, logger: @logger)
  end

  def config
    secret = @credential.secret.to_s
    pat = @credential.pat?

    JiraCore::Config.new(
      project_id: "verify",
      registry: JiraCore::ProjectRegistry.new([]),
      base_url: @connection.base_url,
      jira_base_url: @connection.base_url,
      confluence_base_url: @connection.base_url,
      confluence_web_base_url: @connection.confluence? ? @connection.base_url : nil,
      deployment: @connection.deployment,
      jira_email: @credential.email,
      jira_api_token: !pat && @connection.jira? ? secret : nil,
      jira_pat: pat && @connection.jira? ? secret : nil,
      confluence_email: @credential.email,
      confluence_api_token: !pat && @connection.confluence? ? secret : nil,
      confluence_pat: pat && @connection.confluence? ? secret : nil,
      spaces: [space_key],
      jira_keys: []
    )
  end

  def space_key
    project = Project.joins(team: :memberships)
                     .where(memberships: { user_id: @credential.user_id })
                     .find_by(confluence_connection_id: @connection.id)
    Array(project&.spaces).first || @connection.settings.to_h.fetch("space", "CLD")
  end

  def display_name(data)
    data["displayName"] || data["name"] || data["key"] || data[:name] || data[:key] || "ok"
  end
end
