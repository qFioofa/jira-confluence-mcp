# frozen_string_literal: true

module JiraMcp
  module Tools
    class SearchIssues < MCP::Tool
      tool_name "jira_search_issues"
      title JiraCore::I18n.t("tools.search_issues.title")
      description JiraCore::I18n.t("tools.search_issues.description")
      input_schema(
        type: "object",
        properties: {
          jql: { type: "string", maxLength: 2000, description: JiraCore::I18n.t("args.jql") },
          preset: { type: "string", description: JiraCore::I18n.t("args.preset") },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 25 },
          cursor: { type: "string", description: JiraCore::I18n.t("args.cursor") }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(jql: nil, preset: nil, limit: 25, cursor: nil, server_context: nil)
        Support.run("jira_search_issues") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.search_issues(jql: jql, preset: preset, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
