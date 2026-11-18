# frozen_string_literal: true

module JiraCld
  module Tools
    class TeamWhoKnows < MCP::Tool
      tool_name "team_who_knows"
      title JiraCld::I18n.t("tools.team_who_knows.title")
      description JiraCld::I18n.t("tools.team_who_knows.description")
      input_schema(
        type: "object",
        properties: {
          topic: { type: "string", maxLength: 2000 },
          issue_key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" },
          component: { type: "string" },
          label: { type: "string" },
          window: { type: "integer", minimum: 1, maximum: 3650, default: 180 },
          limit: { type: "integer", minimum: 1, maximum: 20, default: 5 },
          depth: { type: "string", enum: %w[standard deep], default: "standard" }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(topic: nil, issue_key: nil, component: nil, label: nil, window: 180, limit: 5,
                    depth: "standard", server_context: nil)
        Support.run("team_who_knows") do
          runtime = JiraCld.runtime
          runtime.config.require_project!
          Support.ok(runtime.people.who_knows(topic: topic, issue_key: issue_key, component: component,
                                              label: label, window: window, limit: limit, depth: depth))
        end
      end
    end
  end
end
