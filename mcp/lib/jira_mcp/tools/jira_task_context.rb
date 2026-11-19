# frozen_string_literal: true

module JiraMcp
  module Tools
    class JiraTaskContext < MCP::Tool
      tool_name "jira_task_context"
      title JiraCore::I18n.t("tools.jira_task_context.title")
      description JiraCore::I18n.t("tools.jira_task_context.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$", description: JiraCore::I18n.t("args.key") },
          sources: {
            type: "array",
            items: { type: "string", enum: %w[jira kb git people] },
            description: JiraCore::I18n.t("args.task_sources")
          },
          depth: { type: "string", enum: %w[standard deep], default: "standard" },
          since: { type: "string", pattern: "^[0-9]+[dwmy]$", default: "180d", description: JiraCore::I18n.t("args.since") },
          limits: {
            type: "object",
            properties: {
              comments: { type: "integer", minimum: 1, maximum: 100 },
              changelog: { type: "integer", minimum: 1, maximum: 100 },
              similar: { type: "integer", minimum: 1, maximum: 20 },
              kb: { type: "integer", minimum: 1, maximum: 20 },
              commits: { type: "integer", minimum: 1, maximum: 50 },
              people: { type: "integer", minimum: 1, maximum: 20 }
            },
            additionalProperties: false
          }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, sources: nil, depth: "standard", since: "180d", limits: nil, server_context: nil)
        Support.run("jira_task_context") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          Support.ok(runtime.context.task_context(key, sources: sources, depth: depth, since: since, limits: limits))
        end
      end
    end
  end
end
