# frozen_string_literal: true

module JiraCld
  module Tools
    class TeamPrepareQuestion < MCP::Tool
      tool_name "team_prepare_question"
      title JiraCld::I18n.t("tools.team_prepare_question.title")
      description JiraCld::I18n.t("tools.team_prepare_question.description")
      input_schema(
        type: "object",
        properties: {
          issue_key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" },
          topic: { type: "string", maxLength: 2000 },
          person: { type: "string" },
          goal: { type: "string", maxLength: 2000 },
          context: { type: "string", maxLength: 4000 },
          urgency: { type: "string", enum: %w[low normal high], default: "normal" }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(issue_key: nil, topic: nil, person: nil, goal: nil, context: nil, urgency: "normal",
                    server_context: nil)
        Support.run("team_prepare_question") do
          runtime = JiraCld.runtime
          runtime.config.require_project!
          Support.ok(runtime.people.prepare_question(issue_key: issue_key, topic: topic, person: person,
                                                     goal: goal, context: context, urgency: urgency))
        end
      end
    end
  end
end
