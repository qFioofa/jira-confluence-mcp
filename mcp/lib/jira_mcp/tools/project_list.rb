# frozen_string_literal: true

module JiraMcp
  module Tools
    class ProjectList < MCP::Tool
      tool_name "project_list"
      title JiraCore::I18n.t("tools.project_list.title")
      description JiraCore::I18n.t("tools.project_list.description")
      input_schema(type: "object", properties: {}, additionalProperties: false)
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(server_context: nil, **)
        Support.run("project_list") do
          runtime = JiraMcp.runtime
          projects = runtime.config.registry.list.map(&:to_h)
          Support.ok({ "projects" => projects, "bound_project" => runtime.config.project_id })
        end
      end
    end
  end
end
