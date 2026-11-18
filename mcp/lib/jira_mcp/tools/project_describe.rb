# frozen_string_literal: true

module JiraMcp
  module Tools
    class ProjectDescribe < MCP::Tool
      tool_name "project_describe"
      title JiraCore::I18n.t("tools.project_describe.title")
      description JiraCore::I18n.t("tools.project_describe.description")
      input_schema(
        type: "object",
        properties: {
          project_id: { type: "string", description: JiraCore::I18n.t("args.project_id") },
          include_query: { type: "boolean", default: false, description: JiraCore::I18n.t("args.include_query") }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(project_id: nil, include_query: false, server_context: nil)
        Support.run("project_describe") do
          runtime = JiraMcp.runtime
          project_id ||= runtime.config.project_id
          raise JiraCore::ConfigError, "MCP_PROJECT_ID is not set and project_id was not provided" if project_id.nil?

          project = runtime.config.registry.find(project_id)
          raise JiraCore::ConfigError, "unknown project #{project_id.inspect}" unless project

          result = project.describe(include_query: include_query)
          warnings = []
          begin
            metadata = runtime.jira.project_metadata(project.jira_keys.first)
            result.merge!(
              "issue_types" => metadata[:issue_types],
              "components" => metadata[:components],
              "lead" => metadata[:lead]
            )
          rescue StandardError => e
            warnings << { "source" => "jira_project", "code" => error_code(e), "message" => e.message }
          end
          begin
            result["boards"] = runtime.jira.boards[:boards]
          rescue StandardError => e
            warnings << { "source" => "jira_boards", "code" => error_code(e), "message" => e.message }
          end
          result["warnings"] = warnings unless warnings.empty?
          Support.ok(result)
        end
      end

      def self.error_code(error)
        error.respond_to?(:code) ? error.code.to_s : "error"
      end
    end
  end
end
