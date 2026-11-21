# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetBoardIssues < MCP::Tool
      tool_name "jira_get_board_issues"
      title JiraCore::I18n.t("tools.get_board_issues.title")
      description JiraCore::I18n.t("tools.get_board_issues.description")
      input_schema(
        type: "object",
        properties: {
          board_id: { type: "integer", minimum: 1, description: JiraCore::I18n.t("args.board_id") },
          jql: { type: "string", maxLength: 2000, description: JiraCore::I18n.t("args.jql") },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string", description: JiraCore::I18n.t("args.cursor") }
        },
        required: ["board_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(board_id:, jql: nil, limit: 50, cursor: nil, server_context: nil)
        Support.run("jira_get_board_issues") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.board_issues(board_id, jql: jql, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
