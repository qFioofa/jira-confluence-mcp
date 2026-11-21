# frozen_string_literal: true

module JiraMcp
  module Tools
    class ListLinkTypes < MCP::Tool
      tool_name "jira_list_link_types"
      title JiraCore::I18n.t("tools.list_link_types.title")
      description JiraCore::I18n.t("tools.list_link_types.description")
      input_schema(
        type: "object",
        properties: {
          name_filter: { type: "string", maxLength: 100 }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(name_filter: nil, server_context: nil)
        Support.run("jira_list_link_types") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.jira.issue_link_types(name_filter: name_filter))
        end
      end
    end
  end
end
