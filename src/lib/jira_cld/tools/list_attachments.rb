# frozen_string_literal: true

module JiraCld
  module Tools
    class ListAttachments < MCP::Tool
      tool_name "jira_list_attachments"
      title JiraCld::I18n.t("tools.list_attachments.title")
      description JiraCld::I18n.t("tools.list_attachments.description")
      input_schema(
        type: "object",
        properties: { key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" } },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, server_context: nil)
        Support.run("jira_list_attachments") do
          runtime = JiraCld.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.attachments(key))
        end
      end
    end
  end
end
