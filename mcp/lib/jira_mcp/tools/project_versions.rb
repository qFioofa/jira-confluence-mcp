# frozen_string_literal: true

module JiraMcp
  module Tools
    class ProjectVersions < MCP::Tool
      tool_name "jira_project_versions"
      title JiraCore::I18n.t("tools.project_versions.title")
      description JiraCore::I18n.t("tools.project_versions.description")
      input_schema(
        type: "object",
        properties: {
          project_key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*$", description: JiraCore::I18n.t("args.project_key") }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(project_key: nil, server_context: nil)
        Support.run("jira_project_versions") do
          runtime = JiraMcp.runtime
          Support.ok(runtime.jira.project_versions(default_project_key(runtime, project_key)))
        end
      end

      def self.default_project_key(runtime, project_key)
        project_key || runtime.config.jira_keys.first ||
          raise(JiraCore::ConfigError, "project key is not configured; pass project_key")
      end
    end
  end
end
