# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetTransitions < MCP::Tool
      tool_name "jira_get_transitions"
      title JiraCore::I18n.t("tools.get_transitions.title")
      description JiraCore::I18n.t("tools.get_transitions.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$", description: JiraCore::I18n.t("args.key") }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, server_context: nil)
        Support.run("jira_get_transitions") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.jira.transitions(key))
        end
      end
    end
  end
end
