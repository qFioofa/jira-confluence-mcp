# frozen_string_literal: true

module JiraMcp
  module Tools
    class ListFields < MCP::Tool
      tool_name "jira_list_fields"
      title JiraCore::I18n.t("tools.list_fields.title")
      description JiraCore::I18n.t("tools.list_fields.description")
      input_schema(
        type: "object",
        properties: {
          query: { type: "string", maxLength: 200, description: JiraCore::I18n.t("args.field_query") },
          type: { type: "string", maxLength: 50 },
          custom: { type: "boolean" }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(query: nil, type: nil, custom: nil, server_context: nil)
        Support.run("jira_list_fields") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.jira.fields(query: query, type: type, custom: custom))
        end
      end
    end
  end
end
