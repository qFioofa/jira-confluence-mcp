# frozen_string_literal: true

module JiraCld
  module Prompts
    class Handoff < MCP::Prompt
      prompt_name "team:handoff"
      title JiraCld::I18n.t("prompts.handoff.title")
      description JiraCld::I18n.t("prompts.handoff.description")
      arguments [
        MCP::Prompt::Argument.new(name: "issue_key", description: "issue key", required: true),
        MCP::Prompt::Argument.new(name: "person", description: "recipient", required: false)
      ]

      def self.template(args, server_context: nil)
        key = args["issue_key"] || args[:issue_key]
        person = args["person"] || args[:person]
        begin
          brief = Helpers.runtime.issues.brief(key, intent: "plan", depth: "standard")
          question = Helpers.runtime.people.prepare_question(issue_key: key, person: person, goal: "handoff",
                                                             urgency: "normal")
          Helpers.text_result(<<~TEXT, description: JiraCld::I18n.t("prompts.handoff.result"))
            Подготовь передачу задачи #{key}. Структура: состояние, решения, открытые вопросы, следующий шаг,
            риски, кому и что спросить. Не отправляй сообщения; только текст пакета.

            Brief:
            #{Helpers.json(brief)}

            Question packet:
            #{Helpers.json(question)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Подготовь передачу задачи #{key}. Данные получить не удалось: #{Helpers.error_text(e)}.")
        end
      end
    end
  end
end
