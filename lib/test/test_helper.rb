# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "webmock/minitest"
require "json"
require "base64"
require "jira_core"

WebMock.disable_net_connect!(allow_localhost: true)

class CoreTest < Minitest::Test
  def setup
    WebMock.reset!
  end

  def config(overrides = {})
    defaults = {
      project_id: "alpha",
      registry: registry,
      base_url: "https://example.atlassian.net",
      jira_base_url: "https://example.atlassian.net",
      confluence_base_url: "https://example.atlassian.net/wiki",
      deployment: "cloud",
      jira_email: "dev@example.com",
      jira_api_token: "test-token",
      confluence_email: "dev@example.com",
      confluence_api_token: "test-token",
      confluence_pat: "test-pat",
      spaces: ["CLD"],
      jira_keys: ["CLD"]
    }
    JiraCore::Config.new(**defaults.merge(overrides))
  end

  def registry
    JiraCore::ProjectRegistry.new(
      [
        {
          "id" => "alpha",
          "name" => "Alpha",
          "jira_keys" => ["CLD"],
          "spaces" => ["CLD"],
          "style" => "scrum",
          "queries" => {
            "jql" => {
              "blocked" => {
                "label" => "Blocked",
                "query" => "status = Blocked OR flagged = Impediment",
                "order_by" => "priority DESC",
                "default_limit" => 20
              },
              "my_work" => {
                "label" => "My work",
                "query" => "assignee = currentUser() AND statusCategory != Done",
                "order_by" => "updated DESC",
                "default_limit" => 20
              }
            },
            "cql" => {}
          }
        }
      ]
    )
  end
end
