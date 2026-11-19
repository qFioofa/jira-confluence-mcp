# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetIssueLinks < MCP::Tool
      tool_name "jira_get_issue_links"
      title JiraCore::I18n.t("tools.get_issue_links.title")
      description JiraCore::I18n.t("tools.get_issue_links.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$", description: JiraCore::I18n.t("args.key") }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, server_context: nil)
        Support.run("jira_get_issue_links") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.issue_links(key))
        end
      end
    end
  end
end
