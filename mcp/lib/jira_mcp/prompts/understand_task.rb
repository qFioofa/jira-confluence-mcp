# frozen_string_literal: true

module JiraMcp
  module Prompts
    class UnderstandTask < MCP::Prompt
      prompt_name "jira:understand-task"
      title JiraCore::I18n.t("prompts.understand_task.title")
      description JiraCore::I18n.t("prompts.understand_task.description")
      arguments [
        MCP::Prompt::Argument.new(name: "key", description: "issue key", required: true),
        MCP::Prompt::Argument.new(name: "sources", description: "jira,kb,git,people", required: false)
      ]

      def self.template(args, server_context: nil)
        key = args["key"] || args[:key]
        sources = (args["sources"] || args[:sources])
        sources = sources.split(",") if sources.is_a?(String)
        begin
          data = Helpers.runtime.context.task_context(key, sources: sources, depth: "deep")
          Helpers.text_result(<<~TEXT, description: JiraCore::I18n.t("prompts.understand_task.result"))
            Объясни суть задачи #{key}. Структура: суть и цель, scope/non-goals, текущее состояние,
            недавние изменения, зависимости, риски и что неизвестно. Каждое утверждение подкрепи
            ссылкой из citations. Используй git только как evidence. Если данных не хватает — перечисли
            gaps и не заполняй пробелы догадками. Знающего человека упомяни как сигнал, не как факт.

            Данные:
            #{Helpers.json(data)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Объясни суть задачи #{key}. Данные получить не удалось: #{Helpers.error_text(e)}. " \
                              "Вызови jira_task_context key=#{key}.")
        end
      end
    end
  end
end
