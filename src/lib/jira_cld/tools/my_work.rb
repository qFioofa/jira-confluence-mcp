# frozen_string_literal: true

module JiraCld
  module Tools
    class MyWork < MCP::Tool
      tool_name "jira_my_work"
      title JiraCld::I18n.t("tools.my_work.title")
      description JiraCld::I18n.t("tools.my_work.description")
      input_schema(
        type: "object",
        properties: {
          scope: {
            type: "string",
            enum: %w[assigned sprint review blocked recent],
            default: "assigned",
            description: JiraCld::I18n.t("args.scope")
          },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 20 },
          project_id: { type: "string", description: JiraCld::I18n.t("args.project_id") }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(scope: "assigned", limit: 20, project_id: nil, server_context: nil)
        Support.run("jira_my_work") do
          runtime = JiraCld.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.my_work(scope: scope, limit: limit, project_id: project_id))
        end
      end
    end
  end
end
