# frozen_string_literal: true

module JiraMcp
  module Tools
    class KBGetPage < MCP::Tool
      tool_name "kb_get_page"
      title JiraCore::I18n.t("tools.kb_get_page.title")
      description JiraCore::I18n.t("tools.kb_get_page.description")
      input_schema(
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          space: { type: "string" }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(id: nil, title: nil, space: nil, server_context: nil)
        Support.run("kb_get_page") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.knowledge_base.get_page(id: id, title: title, space: space))
        end
      end
    end
  end
end
