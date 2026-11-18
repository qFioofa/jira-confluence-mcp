# frozen_string_literal: true

module JiraCld
  module Tools
    class ProjectResolve < MCP::Tool
      tool_name "project_resolve"
      title JiraCld::I18n.t("tools.project_resolve.title")
      description JiraCld::I18n.t("tools.project_resolve.description")
      input_schema(
        type: "object",
        properties: { query: { type: "string", minLength: 1, maxLength: 200 } },
        required: ["query"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(query:, server_context: nil)
        Support.run("project_resolve") do
          runtime = JiraCld.runtime
          result = runtime.config.registry.resolve(query)
          result["bound_project"] = runtime.config.project_id
          result["note"] = "candidates are metadata only; resolving does not change the bound project"
          Support.ok(result)
        end
      end
    end
  end
end
