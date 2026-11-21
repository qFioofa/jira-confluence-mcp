# frozen_string_literal: true

module JiraMcp
  module Tools
    class ListBoards < MCP::Tool
      tool_name "jira_list_boards"
      title JiraCore::I18n.t("tools.list_boards.title")
      description JiraCore::I18n.t("tools.list_boards.description")
      input_schema(
        type: "object",
        properties: {
          project_key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*$", description: JiraCore::I18n.t("args.project_key") },
          name: { type: "string", maxLength: 200 },
          type: { type: "string", enum: %w[scrum kanban simple] },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string", description: JiraCore::I18n.t("args.cursor") }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(project_key: nil, name: nil, type: nil, limit: 50, cursor: nil, server_context: nil)
        Support.run("jira_list_boards") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.boards(project_key: project_key, name: name, type: type,
                                           limit: limit, cursor: cursor))
        end
      end
    end
  end
end
