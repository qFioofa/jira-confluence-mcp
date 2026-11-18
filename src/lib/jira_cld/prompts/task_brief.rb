# frozen_string_literal: true

module JiraCld
  module Prompts
    class TaskBrief < MCP::Prompt
      prompt_name "jira:task-brief"
      title JiraCld::I18n.t("prompts.task_brief.title")
      description JiraCld::I18n.t("prompts.task_brief.description")
      arguments [
        MCP::Prompt::Argument.new(name: "key", description: "issue key", required: true),
        MCP::Prompt::Argument.new(name: "intent", description: "understand | plan | verify", required: false)
      ]

      def self.template(args, server_context: nil)
        key = args["key"] || args[:key]
        intent = args["intent"] || args[:intent] || "understand"
        begin
          data = Helpers.runtime.issues.brief(key, intent: intent, depth: "deep")
          Helpers.text_result(<<~TEXT, description: JiraCld::I18n.t("prompts.task_brief.result"))
            Подготовь brief задачи #{key} с intent=#{intent}.
            Опирайся только на issue, acceptance_criteria, comments, decisions, dependencies, similar и knowledge_base.
            Если данных не хватает — перечисли gaps и задай вопросы, а не заполняй пробелы догадками.
            Для intent=verify преврати acceptance_criteria в проверяемый чек-лист.

            Данные:
            #{Helpers.json(data)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Подготовь brief задачи #{key}. Данные получить не удалось: #{Helpers.error_text(e)}. " \
                              "Вызови jira_brief_issue key=#{key}.")
        end
      end
    end
  end
end
