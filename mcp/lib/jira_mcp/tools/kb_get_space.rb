# frozen_string_literal: true

module JiraMcp
  module Tools
    class KBGetSpace < MCP::Tool
      tool_name "kb_get_space"
      title JiraCore::I18n.t("tools.kb_get_space.title")
      description JiraCore::I18n.t("tools.kb_get_space.description")
      input_schema(
        type: "object",
        properties: {
          space: { type: "string", maxLength: 100, description: JiraCore::I18n.t("args.space") }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(space: nil, server_context: nil)
        Support.run("kb_get_space") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.knowledge_base.space_info(space: space))
        end
      end
    end
  end
end
