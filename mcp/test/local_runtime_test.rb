# frozen_string_literal: true

require_relative "test_helper"

class LocalRuntimeTest < Minitest::Test
  BASE_ENV = {
    "MCP_PROJECT_ID" => "alpha",
    "JIRA_BASE_URL" => "https://example.atlassian.net",
    "JIRA_EMAIL" => "dev@example.com",
    "JIRA_API_TOKEN" => "test-token"
  }.freeze

  def test_builds_runtime_from_env
    runtime = JiraMcp::LocalRuntime.from_env(
      BASE_ENV.merge("CLD_SPACE" => "CLD", "JIRA_KEYS" => "cld,ops", "MCP_PROJECT_NAME" => "Alpha")
    )

    assert_equal "alpha", runtime.config.project_id
    assert_equal ["CLD", "OPS"], runtime.config.jira_keys
    assert_equal ["CLD"], runtime.config.spaces
    assert_equal "Alpha", runtime.config.project.name
  ensure
    runtime&.close
  end

  def test_defaults_project_key_and_cache
    runtime = JiraMcp::LocalRuntime.from_env(BASE_ENV)

    assert_equal ["ALPHA"], runtime.config.jira_keys
    assert_instance_of JiraCore::Cache::MemoryStore, runtime.cache
  ensure
    runtime&.close
  end

  def test_requires_project_id
    error = assert_raises(JiraMcp::LocalRuntime::ConfigError) do
      JiraMcp::LocalRuntime.from_env(BASE_ENV.reject { |key, _| key == "MCP_PROJECT_ID" })
    end

    assert_match(/MCP_PROJECT_ID/, error.message)
  end

  def test_requires_jira_credentials
    env = BASE_ENV.reject { |key, _| key == "JIRA_API_TOKEN" }

    error = assert_raises(JiraMcp::LocalRuntime::ConfigError) do
      JiraMcp::LocalRuntime.from_env(env)
    end

    assert_match(/JIRA_API_TOKEN or JIRA_PAT/, error.message)
  end

  def test_rejects_non_integer_values
    error = assert_raises(JiraMcp::LocalRuntime::ConfigError) do
      JiraMcp::LocalRuntime.from_env(BASE_ENV.merge("OUTPUT_CHAR_LIMIT" => "many"))
    end

    assert_match(/OUTPUT_CHAR_LIMIT/, error.message)
  end
end
