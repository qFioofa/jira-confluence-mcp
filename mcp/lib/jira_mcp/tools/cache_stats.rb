# frozen_string_literal: true

module JiraMcp
  module Tools
    class CacheStats < MCP::Tool
      tool_name "atlassian_cache_stats"
      title JiraCore::I18n.t("tools.cache_stats.title")
      description JiraCore::I18n.t("tools.cache_stats.description")
      input_schema(type: "object", properties: {}, additionalProperties: false)
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(server_context: nil, **)
        Support.run("atlassian_cache_stats") do
          runtime = JiraMcp.runtime
          Support.ok({ "cache" => runtime.cache_stats })
        end
      end
    end
  end
end
