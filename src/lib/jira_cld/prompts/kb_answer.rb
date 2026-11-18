# frozen_string_literal: true

module JiraCld
  module Prompts
    class KBAnswer < MCP::Prompt
      prompt_name "kb:answer"
      title JiraCld::I18n.t("prompts.kb_answer.title")
      description JiraCld::I18n.t("prompts.kb_answer.description")
      arguments [
        MCP::Prompt::Argument.new(name: "question", description: "question to answer", required: true)
      ]

      def self.template(args, server_context: nil)
        question = args["question"] || args[:question]
        begin
          data = Helpers.runtime.knowledge_base.search(query: question, limit: 10)
          pages = Array(data["pages"]).first(5).map do |page|
            Helpers.runtime.knowledge_base.get_page(id: page["id"])["page"]
          rescue StandardError
            page
          end
          Helpers.text_result(<<~TEXT, description: JiraCld::I18n.t("prompts.kb_answer.result"))
            Ответь на вопрос по базе знаний. Каждое утверждение подкрепи ссылкой на страницу.
            Если в базе нет ответа — скажи об этом явно и предложи, что проверить.

            Вопрос: #{question}

            Страницы:
            #{Helpers.json(pages)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Ответь на вопрос по базе знаний: #{question}. " \
                              "Поиск не удался: #{Helpers.error_text(e)}.")
        end
      end
    end
  end
end
