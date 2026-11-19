# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetWorklog < MCP::Tool
      tool_name "jira_get_worklog"
      title JiraCore::I18n.t("tools.get_worklog.title")
      description JiraCore::I18n.t("tools.get_worklog.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$", description: JiraCore::I18n.t("args.key") },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string", description: JiraCore::I18n.t("args.cursor") }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, limit: 50, cursor: nil, server_context: nil)
        Support.run("jira_get_worklog") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.jira.worklogs(key, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
