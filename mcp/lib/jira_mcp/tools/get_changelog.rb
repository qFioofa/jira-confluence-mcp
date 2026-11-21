# frozen_string_literal: true

module JiraMcp
  module Tools
    class GetChangelog < MCP::Tool
      tool_name "jira_get_changelog"
      title JiraCore::I18n.t("tools.get_changelog.title")
      description JiraCore::I18n.t("tools.get_changelog.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 50 },
          cursor: { type: "string" }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, limit: 50, cursor: nil, server_context: nil)
        Support.run("jira_get_changelog") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          data = runtime.issues.changelog(key, limit: limit, cursor: cursor)
          Support.ok({ "key" => key.upcase, "entries" => data[:entries],
                       "next_cursor" => data[:next_cursor], "total" => data[:total] })
        end
      end
    end
  end
end
