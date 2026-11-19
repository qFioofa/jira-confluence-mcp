# frozen_string_literal: true

module JiraMcp
  module Tools
    class JiraClarifyIssue < MCP::Tool
      tool_name "jira_clarify_issue"
      title JiraCore::I18n.t("tools.jira_clarify_issue.title")
      description JiraCore::I18n.t("tools.jira_clarify_issue.description")
      input_schema(
        type: "object",
        properties: {
          key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$", description: JiraCore::I18n.t("args.key") },
          audience: {
            type: "string", enum: %w[analyst po tech_lead team], default: "analyst",
            description: JiraCore::I18n.t("args.audience")
          },
          focus: {
            type: "array",
            items: {
              type: "string",
              enum: %w[all acceptance scope behavior data_api ux dependencies nfr rollout analytics docs]
            },
            description: JiraCore::I18n.t("args.focus")
          },
          include: {
            type: "array",
            items: { type: "string", enum: %w[jira kb git] },
            description: JiraCore::I18n.t("args.clarify_include")
          },
          max_questions: { type: "integer", minimum: 1, maximum: 20, default: 10 },
          format: { type: "string", enum: %w[json markdown both], default: "both" }
        },
        required: ["key"],
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(key:, audience: "analyst", focus: nil, include: nil, max_questions: 10, format: "both",
                    server_context: nil)
        Support.run("jira_clarify_issue") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          result = runtime.context.clarify_issue(key, audience: audience, focus: focus, include: include,
                                                      max_questions: max_questions)
          payload = if format == "markdown"
                      { "message_markdown" => result["message_markdown"], "readiness" => result["readiness"] }
                    else
                      result
                    end
          Support.ok(payload)
        end
      end
    end
  end
end
