# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib/lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "webmock/minitest"
require "json"
require "jira_mcp"

WebMock.disable_net_connect!(allow_localhost: true)

class McpTest < Minitest::Test
  def setup
    WebMock.reset!
  end

  def runtime
    @runtime ||= JiraCore::Runtime.build(config: config, cache: JiraCore::Cache::MemoryStore.new)
  end

  def config
    JiraCore::Config.new(
      project_id: "alpha",
      registry: registry,
      base_url: "https://example.atlassian.net",
      jira_base_url: "https://example.atlassian.net",
      confluence_base_url: "https://example.atlassian.net/wiki",
      jira_email: "dev@example.com",
      jira_api_token: "test-token",
      confluence_api_token: "test-token",
      spaces: ["CLD"],
      jira_keys: ["CLD"]
    )
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
          "queries" => { "jql" => {}, "cql" => {} }
        }
      ]
    )
  end

  def with_runtime
    JiraMcp.with_runtime(runtime) { yield }
  end
end
