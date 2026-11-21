# frozen_string_literal: true

module JiraMcp
  module Tools
    class KBGetAttachment < MCP::Tool
      tool_name "kb_get_attachment"
      title JiraCore::I18n.t("tools.kb_get_attachment.title")
      description JiraCore::I18n.t("tools.kb_get_attachment.description")
      input_schema(
        type: "object",
        properties: {
          page_id: { type: "string", minLength: 1, description: JiraCore::I18n.t("args.page_id") },
          attachment_id: { type: "string", description: JiraCore::I18n.t("args.kb_attachment_id") },
          filename: { type: "string", maxLength: 255 }
        },
        required: ["page_id"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(page_id:, attachment_id: nil, filename: nil, server_context: nil)
        Support.run("kb_get_attachment") do
          runtime = JiraMcp.runtime
          Support.attachment(runtime.knowledge_base.attachment(page_id, attachment_id: attachment_id,
                                                                          filename: filename))
        end
      end
    end
  end
end
