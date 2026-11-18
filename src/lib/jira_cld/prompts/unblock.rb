# frozen_string_literal: true

module JiraCld
  module Prompts
    class Unblock < MCP::Prompt
      prompt_name "jira:unblock"
      title JiraCld::I18n.t("prompts.unblock.title")
      description JiraCld::I18n.t("prompts.unblock.description")
      arguments [
        MCP::Prompt::Argument.new(name: "key", description: "issue key", required: false),
        MCP::Prompt::Argument.new(name: "query", description: "problem description", required: false),
        MCP::Prompt::Argument.new(name: "symptom", description: "observed symptom", required: false)
      ]

      def self.template(args, server_context: nil)
        key = args["key"] || args[:key]
        query = args["query"] || args[:query]
        symptom = args["symptom"] || args[:symptom]
        begin
          data = Helpers.runtime.issues.unblock(key: key, query: query, symptom: symptom, window: "30d", limit: 5)
          Helpers.text_result(<<~TEXT, description: JiraCld::I18n.t("prompts.unblock.result"))
            Разбери ступор. Используй prior art (similar_resolved), experts, recent_changes, runbooks,
            hypotheses и questions. Не утверждай причину без evidence. Дай 3–5 вопросов команде.

            Данные:
            #{Helpers.json(data)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Разбери ступор. Данные получить не удалось: #{Helpers.error_text(e)}. " \
                              "Вызови jira_unblock_issue.")
        end
      end
    end
  end
end
