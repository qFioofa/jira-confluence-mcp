# frozen_string_literal: true

module JiraCld
  module Prompts
    class Daily < MCP::Prompt
      prompt_name "jira:daily"
      title JiraCld::I18n.t("prompts.daily.title")
      description JiraCld::I18n.t("prompts.daily.description")
      arguments [
        MCP::Prompt::Argument.new(name: "scope", description: JiraCld::I18n.t("args.scope"), required: false),
        MCP::Prompt::Argument.new(name: "limit", description: "issues to include (default 20)", required: false)
      ]

      def self.template(args, server_context: nil)
        scope = args["scope"] || args[:scope] || "assigned"
        limit = (args["limit"] || args[:limit] || 20).to_i
        begin
          data = Helpers.runtime.issues.my_work(scope: scope, limit: limit)
          Helpers.text_result(<<~TEXT, description: JiraCld::I18n.t("prompts.daily.result"))
            Составь стендап-сводку по задачам ниже.
            Для каждой задачи: что сделано, что дальше, что мешает. Не выдумывай факты.
            Используй только поля issues и явно отмечай missing data.

            Данные:
            #{Helpers.json(data)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Собери стендап по проекту. Данные получить не удалось: #{Helpers.error_text(e)}. " \
                              "Запроси их через jira_my_work.")
        end
      end
    end
  end
end
