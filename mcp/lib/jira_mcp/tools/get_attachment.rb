# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetAttachment < MCP::Tool
      tool_name "jira_get_attachment"
      title JiraCore::I18n.t("tools.get_attachment.title")
      description JiraCore::I18n.t("tools.get_attachment.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$", description: JiraCore::I18n.t("args.key") },
          attachment_id: { type: "string", description: JiraCore::I18n.t("args.attachment_id") },
          filename: { type: "string", maxLength: 255 }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, attachment_id: nil, filename: nil, server_context: nil)
        Support.run("jira_get_attachment") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.attachment(runtime.jira.attachment(key, id: attachment_id, filename: filename))
        end
      end
    end
  end
end
