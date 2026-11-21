# frozen_string_literal: true

module JiraMcp
  module Prompts
    class ClarifyAnalyst < MCP::Prompt
      prompt_name "jira:clarify-analyst"
      title JiraCore::I18n.t("prompts.clarify_analyst.title")
      description JiraCore::I18n.t("prompts.clarify_analyst.description")
      arguments [
        MCP::Prompt::Argument.new(name: "key", description: "issue key", required: true),
        MCP::Prompt::Argument.new(name: "audience", description: "analyst|po|tech_lead|team", required: false)
      ]

      def self.template(args, server_context: nil)
        key = args["key"] || args[:key]
        audience = args["audience"] || args[:audience] || "analyst"
        begin
          data = Helpers.runtime.context.clarify_issue(key, audience: audience, max_questions: 10)
          Helpers.text_result(<<~TEXT, description: JiraCore::I18n.t("prompts.clarify_analyst.result"))
            Сформируй сообщение для #{audience} по задаче #{key}. Используй readiness и questions:
            сначала blocking, затем high/medium. Каждый вопрос — с why_it_matters и ссылкой на evidence.
            Если вопрос уже покрыт KB — отметь это, а не спрашивай повторно. В конце укажи recipients
            с пояснением, почему этот человек. Не добавляй вопросов без evidence и не отправляй сообщение.

            Данные:
            #{Helpers.json(data)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Сформируй вопросы для #{audience} по задаче #{key}. " \
                              "Данные получить не удалось: #{Helpers.error_text(e)}. " \
                              "Вызови jira_clarify_issue key=#{key}.")
        end
      end
    end
  end
end
