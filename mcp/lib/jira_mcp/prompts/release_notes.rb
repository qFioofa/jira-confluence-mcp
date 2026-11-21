# frozen_string_literal: true

module JiraMcp
  module Prompts
    class ReleaseNotes < MCP::Prompt
      prompt_name "jira:release-notes"
      title JiraCore::I18n.t("prompts.release_notes.title")
      description JiraCore::I18n.t("prompts.release_notes.description")
      arguments [
        MCP::Prompt::Argument.new(name: "preset", description: "JQL preset id", required: false),
        MCP::Prompt::Argument.new(name: "version", description: "release version", required: false)
      ]

      def self.template(args, server_context: nil)
        preset = args["preset"] || args[:preset] || "release_notes"
        version = args["version"] || args[:version]
        begin
          data = Helpers.runtime.issues.search_issues(preset: preset, limit: 50)
          scope = version ? "Версия: #{version}." : "Все незарелиженные исправления."
          Helpers.text_result(<<~TEXT, description: JiraCore::I18n.t("prompts.release_notes.result"))
            Составь релиз-ноты из задач ниже. Группируй по типу: features, fixes, improvements.
            Формат: короткий заголовок + ключ задачи + ссылка. Не добавляй задачи, которых нет в данных.
            #{scope}

            Данные:
            #{Helpers.json(data)}
          TEXT
        rescue StandardError => e
          Helpers.text_result("Составь релиз-ноты. Данные получить не удалось: #{Helpers.error_text(e)}. " \
                              "Используй jira_search_issues с preset=#{preset}.")
        end
      end
    end
  end
end
