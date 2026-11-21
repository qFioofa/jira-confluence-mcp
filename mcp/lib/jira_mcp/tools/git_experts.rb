# frozen_string_literal: true

module JiraMcp
  module Tools
    class GitExperts < MCP::Tool
      tool_name "git_experts"
      title JiraCore::I18n.t("tools.git_experts.title")
      description JiraCore::I18n.t("tools.git_experts.description")
      input_schema(
        type: "object",
        properties: {
          issue_key: { type: "string", pattern: "^[A-Za-z][A-Za-z0-9_]*-[0-9]+$" },
          repo: { type: "string", maxLength: 100 },
          path: { type: "string", maxLength: 500 },
          component: { type: "string", maxLength: 200 },
          since: { type: "string", pattern: "^[0-9]+[dwmy]$", default: "180d" },
          limit: { type: "integer", minimum: 1, maximum: 20, default: 5 }
        },
        additionalProperties: false
      )
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(issue_key: nil, repo: nil, path: nil, component: nil, since: "180d", limit: 5,
                    server_context: nil)
        Support.run("git_experts") do
          runtime = JiraMcp.runtime
          runtime.config.require_project!
          raise JiraCore::ConfigError, "local git repositories are not configured" unless runtime.git.enabled?

          Support.ok(runtime.git.experts(issue_key: issue_key, repo: repo, path: path, component: component,
                                         since: since, limit: limit))
        end
      end
    end
  end
end
