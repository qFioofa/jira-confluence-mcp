# frozen_string_literal: true

module JiraCld
  module Tools
    class KBListChildren < MCP::Tool
      tool_name "kb_list_children"
      title JiraCld::I18n.t("tools.kb_list_children.title")
      description JiraCld::I18n.t("tools.kb_list_children.description")
      input_schema(
        type: "object",
        properties: {
          page_id: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string" }
        },
        required: ["page_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(page_id:, limit: 50, cursor: nil, server_context: nil)
        Support.run("kb_list_children") do
          runtime = JiraCld.runtime
          Support.ok(runtime.knowledge_base.list_children(page_id, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
