# frozen_string_literal: true

require "mcp"

module JiraMcp
  class ServerBuilder
    PROTOCOL_VERSION = "2025-11-25"

    TOOLS = [
      Tools::ProjectList,
      Tools::ProjectDescribe,
      Tools::ProjectResolve,
      Tools::ListBoards,
      Tools::GetBoardIssues,
      Tools::ListFields,
      Tools::GetFieldOptions,
      Tools::GetTransitions,
      Tools::SearchUsers,
      Tools::ListLinkTypes,
      Tools::ProjectVersions,
      Tools::ProjectComponents,
      Tools::GitExperts,
      Tools::MyWork,
      Tools::SearchIssues,
      Tools::GetIssue,
      Tools::BriefIssue,
      Tools::JiraTaskContext,
      Tools::JiraClarifyIssue,
      Tools::GetChangelog,
      Tools::GetIssueLinks,
      Tools::GetWorklog,
      Tools::ListAttachments,
      Tools::GetAttachment,
      Tools::UnblockIssue,
      Tools::ListSprints,
      Tools::GetSprintIssues,
      Tools::KBSearch,
      Tools::KBGetPage,
      Tools::KBGetSpace,
      Tools::KBGetPageHistory,
      Tools::KBGetPageComments,
      Tools::KBListLabels,
      Tools::KBListChildren,
      Tools::KBListAttachments,
      Tools::KBGetAttachment,
      Tools::KBSpaceTree,
      Tools::TeamWhoKnows,
      Tools::TeamPrepareQuestion,
      Tools::Whoami,
      Tools::CacheStats
    ].freeze

    PROMPTS = [
      Prompts::Daily,
      Prompts::ReleaseNotes,
      Prompts::TaskBrief,
      Prompts::UnderstandTask,
      Prompts::ClarifyAnalyst,
      Prompts::Unblock,
      Prompts::Handoff,
      Prompts::KBAnswer
    ].freeze

    RESOURCE_TEMPLATES = [
      Resources::JiraIssueTemplate,
      Resources::KBPageTemplate
    ].freeze

    attr_reader :runtime, :mcp

    def self.build(runtime:, server_context: {})
      new(runtime: runtime, server_context: server_context).mcp
    end

    def initialize(runtime:, server_context: {})
      @runtime = runtime
      @server_context = server_context.merge(runtime: runtime)
      configure_mcp
      @mcp = MCP::Server.new(
        name: "jira-web",
        title: "jira-web",
        version: JiraMcp::VERSION,
        instructions: JiraCore::I18n.t("server.instructions", project: runtime.config.project_id || "unbound"),
        tools: TOOLS,
        prompts: PROMPTS,
        resource_templates: RESOURCE_TEMPLATES,
        page_size: 50,
        ttl_ms: 60_000,
        cache_scope: "private",
        server_context: @server_context
      )
    end

    private

    def configure_mcp
      MCP.configure do |configuration|
        configuration.protocol_version = PROTOCOL_VERSION
        configuration.validate_tool_call_arguments = true
        configuration.validate_tool_call_results = false
      end
    end
  end
end
