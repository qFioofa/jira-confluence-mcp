# frozen_string_literal: true

module JiraCld
  module Tools
    class GetSprintIssues < MCP::Tool
      tool_name "jira_get_sprint_issues"
      title JiraCld::I18n.t("tools.get_sprint_issues.title")
      description JiraCld::I18n.t("tools.get_sprint_issues.description")
      input_schema(
        type: "object",
        properties: {
          sprint_id: { type: "integer", minimum: 1 },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string" }
        },
        required: ["sprint_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(sprint_id:, limit: 50, cursor: nil, server_context: nil)
        Support.run("jira_get_sprint_issues") do
          runtime = JiraCld.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.sprint_issues(sprint_id, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
