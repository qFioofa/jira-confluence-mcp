# frozen_string_literal: true

module JiraCld
  module Tools
    class CacheStats < MCP::Tool
      tool_name "atlassian_cache_stats"
      title JiraCld::I18n.t("tools.cache_stats.title")
      description JiraCld::I18n.t("tools.cache_stats.description")
      input_schema(type: "object", properties: {}, additionalProperties: false)
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(server_context: nil, **)
        Support.run("atlassian_cache_stats") do
          runtime = JiraCld.runtime
          runtime.stats_writer.flush!
          Support.ok(
            {
              "cache" => runtime.cache_stats,
              "stats" => runtime.stats_query.summary(project: runtime.config.project_id, range: "1h")
            }
          )
        end
      end
    end
  end
end
