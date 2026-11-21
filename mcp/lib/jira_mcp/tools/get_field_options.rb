# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetFieldOptions < MCP::Tool
      tool_name "jira_get_field_options"
      title JiraCore::I18n.t("tools.get_field_options.title")
      description JiraCore::I18n.t("tools.get_field_options.description")
      input_schema(
        type: "object",
        properties: {
          field_id: { type: "string", minLength: 1, maxLength: 100, description: JiraCore::I18n.t("args.field_id") },
          query: { type: "string", maxLength: 200 },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 }
        },
        required: ["field_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(field_id:, query: nil, limit: 50, server_context: nil)
        Support.run("jira_get_field_options") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.jira.field_options(field_id, query: query, limit: limit))
        end
      end
    end
  end
end
