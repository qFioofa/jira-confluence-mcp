# frozen_string_literal: true

require "json"

module JiraCld
  module Resources
    class JiraIssueTemplate < MCP::ResourceTemplate
      uri_template "jira://issue/{key}"
      resource_template_name "jira_issue"
      title JiraCld::I18n.t("resources.jira_issue.title")
      description JiraCld::I18n.t("resources.jira_issue.description")
      mime_type "application/json"

      def self.contents(key:, server_context: nil)
        data = JiraCld.runtime.issues.get_issue(key, include: %w[comments links])
        MCP::Resource::TextContents.new(
          uri: "jira://issue/#{key}",
          mime_type: "application/json",
          text: JSON.pretty_generate(Tools::Support.normalize(data))
        )
      rescue StandardError => e
        MCP::Resource::TextContents.new(
          uri: "jira://issue/#{key}",
          mime_type: "application/json",
          text: JSON.pretty_generate("error" => { "code" => "resource_error", "message" => e.message })
        )
      end
    end
  end
end
