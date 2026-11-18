# frozen_string_literal: true

module JiraCld
  module Tools
    class KBSearch < MCP::Tool
      tool_name "kb_search"
      title JiraCld::I18n.t("tools.kb_search.title")
      description JiraCld::I18n.t("tools.kb_search.description")
      input_schema(
        type: "object",
        properties: {
          query: { type: "string", maxLength: 2000, description: JiraCld::I18n.t("args.kb_query") },
          cql: { type: "string", maxLength: 2000 },
          preset: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 10 },
          cursor: { type: "string" }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(query: nil, cql: nil, preset: nil, limit: 10, cursor: nil, server_context: nil)
        Support.run("kb_search") do
          runtime = JiraCld.runtime
          Support.ok(runtime.knowledge_base.search(query: query, cql: cql, preset: preset, limit: limit, cursor: cursor))
        end
      end
    end
  end
end
