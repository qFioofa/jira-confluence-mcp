# frozen_string_literal: true

module JiraMcp
  module Tools
    class KBSpaceTree < MCP::Tool
      tool_name "kb_space_tree"
      title JiraCore::I18n.t("tools.kb_space_tree.title")
      description JiraCore::I18n.t("tools.kb_space_tree.description")
      input_schema(
        type: "object",
        properties: {
          space: { type: "string", maxLength: 100, description: JiraCore::I18n.t("args.space") },
          depth: { type: "integer", minimum: 1, maximum: 5, default: 2, description: JiraCore::I18n.t("args.depth") },
          limit: { type: "integer", minimum: 1, maximum: 500, default: 100 }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(space: nil, depth: 2, limit: 100, server_context: nil)
        Support.run("kb_space_tree") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.knowledge_base.space_tree(space: space, depth: depth, limit: limit))
        end
      end
    end
  end
end
