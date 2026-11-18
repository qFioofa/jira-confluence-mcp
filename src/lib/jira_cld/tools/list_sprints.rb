# frozen_string_literal: true

module JiraCld
  module Tools
    class ListSprints < MCP::Tool
      tool_name "jira_list_sprints"
      title JiraCld::I18n.t("tools.list_sprints.title")
      description JiraCld::I18n.t("tools.list_sprints.description")
      input_schema(
        type: "object",
        properties: {
          board_id: { type: "integer", minimum: 1 },
          state: { type: "string", enum: %w[active future closed] }
        },
        required: ["board_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(board_id:, state: nil, server_context: nil)
        Support.run("jira_list_sprints") do
          runtime = JiraCld.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.sprints(board_id, state: state))
        end
      end
    end
  end
end
