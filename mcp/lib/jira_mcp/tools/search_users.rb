# frozen_string_literal: true

module JiraMcp
  module Tools
    class SearchUsers < MCP::Tool
      tool_name "jira_search_users"
      title JiraCore::I18n.t("tools.search_users.title")
      description JiraCore::I18n.t("tools.search_users.description")
      input_schema(
        type: "object",
        properties: {
          query: { type: "string", minLength: 1, maxLength: 200, description: JiraCore::I18n.t("args.user_query") },
          project_key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*$", description: JiraCore::I18n.t("args.project_key") },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 20 }
        },
        required: ["query"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(query:, project_key: nil, limit: 20, server_context: nil)
        Support.run("jira_search_users") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.jira.search_users(query, project_key: project_key, limit: limit))
        end
      end
    end
  end
end
