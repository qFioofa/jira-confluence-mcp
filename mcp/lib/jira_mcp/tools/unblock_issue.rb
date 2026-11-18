# frozen_string_literal: true

module JiraMcp
  module Tools
    class UnblockIssue < MCP::Tool
      tool_name "jira_unblock_issue"
      title JiraCore::I18n.t("tools.unblock_issue.title")
      description JiraCore::I18n.t("tools.unblock_issue.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" },
          query: { type: "string", maxLength: 2000 },
          symptom: { type: "string", maxLength: 2000 },
          window: { type: "string", pattern: "^[0-9]+[dw]$", default: "30d" },
          limit: { type: "integer", minimum: 1, maximum: 20, default: 5 }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key: nil, query: nil, symptom: nil, window: "30d", limit: 5, server_context: nil)
        Support.run("jira_unblock_issue") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.unblock(key: key, query: query, symptom: symptom, window: window, limit: limit))
        end
      end
    end
  end
end
