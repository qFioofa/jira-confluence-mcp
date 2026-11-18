# frozen_string_literal: true

module JiraCld
  module Tools
    class Whoami < MCP::Tool
      tool_name "atlassian_whoami"
      title JiraCld::I18n.t("tools.whoami.title")
      description JiraCld::I18n.t("tools.whoami.description")
      input_schema(type: "object", properties: {}, additionalProperties: false)
      output_schema(type: "object", additionalProperties: true)
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

      def self.call(server_context: nil, **)
        Support.run("atlassian_whoami") do
          runtime = JiraCld.runtime
          Support.ok(runtime.whoami)
        end
      end
    end
  end
end
