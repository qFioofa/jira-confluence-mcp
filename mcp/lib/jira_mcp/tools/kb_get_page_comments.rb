# frozen_string_literal: true

module JiraMcp
  module Tools
    class KBGetPageComments < MCP::Tool
      tool_name "kb_get_page_comments"
      title JiraCore::I18n.t("tools.kb_get_page_comments.title")
      description JiraCore::I18n.t("tools.kb_get_page_comments.description")
      input_schema(
        type: "object",
        properties: {
          page_id: { type: "string", minLength: 1, description: JiraCore::I18n.t("args.page_id") },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string", description: JiraCore::I18n.t("args.cursor") }
        },
        required: ["page_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(page_id:, limit: 50, cursor: nil, server_context: nil)
        Support.run("kb_get_page_comments") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.knowledge_base.page_comments(page_id, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
