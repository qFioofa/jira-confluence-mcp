# frozen_string_literal: true

module JiraMcp
  module Tools
    class BriefIssue < MCP::Tool
      tool_name "jira_brief_issue"
      title JiraCore::I18n.t("tools.brief_issue.title")
      description JiraCore::I18n.t("tools.brief_issue.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" },
          intent: { type: "string", enum: %w[understand plan verify], default: "understand" },
          depth: { type: "string", enum: %w[standard deep], default: "standard" },
          include: {
            type: "array",
            items: { type: "string", enum: %w[comments changelog links similar kb] }
          },
          limits: {
            type: "object",
            properties: {
              comments: { type: "integer", minimum: 1, maximum: 100 },
              changelog: { type: "integer", minimum: 1, maximum: 100 },
              similar: { type: "integer", minimum: 1, maximum: 20 },
              kb: { type: "integer", minimum: 1, maximum: 20 }
            },
            additionalProperties: false
          }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, intent: "understand", depth: "standard", include: nil, limits: nil, server_context: nil)
        Support.run("jira_brief_issue") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.issues.brief(key, intent: intent, depth: depth, include: include, limits: limits))
        end
      end
    end
  end
end
