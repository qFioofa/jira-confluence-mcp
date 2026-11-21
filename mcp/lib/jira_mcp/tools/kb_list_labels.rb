# frozen_string_literal: true

module JiraMcp
  module Tools
    class KBListLabels < MCP::Tool
      tool_name "kb_list_labels"
      title JiraCore::I18n.t("tools.kb_list_labels.title")
      description JiraCore::I18n.t("tools.kb_list_labels.description")
      input_schema(
        type: "object",
        properties: {
          page_id: { type: "string", minLength: 1, description: JiraCore::I18n.t("args.page_id") }
        },
        required: ["page_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(page_id:, server_context: nil)
        Support.run("kb_list_labels") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.knowledge_base.labels(page_id))
        end
      end
    end
  end
end
