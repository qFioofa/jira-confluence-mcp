# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

ENV["RACK_ENV"] ||= "test"

require "minitest/autorun"
require "webmock/minitest"
require "tmpdir"
require "fileutils"
require "json"
require "jira_cld"

WebMock.disable_net_connect!(allow_localhost: true)

JiraCld::I18n.setup(locale: "ru")

class BaseTest < Minitest::Test
  def setup
    WebMock.reset!
    @tmp = Dir.mktmpdir("jira-cld-test-")
    @config_path = File.join(@tmp, "config.yml")
    @data_dir = File.join(@tmp, "data")
    JiraCld.runtime = nil
    JiraCld::DB.disconnect!
  end

  def teardown
    JiraCld.runtime&.close
    JiraCld.runtime = nil
    JiraCld::DB.disconnect!
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  def write_config(projects: nil, jira: {}, confluence: {})
    store = JiraCld::ConfigStore.new(path: @config_path)
    document = JiraCld::ConfigStore.default_document
    document["connections"]["jira"] = document["connections"]["jira"].merge(
      { "base_url" => "https://example.atlassian.net", "deployment" => "cloud",
        "token_ref" => "env:JIRA_API_TOKEN", "email" => "dev@example.com" }.merge(jira)
    )
    document["connections"]["confluence"] = document["connections"]["confluence"].merge(
      { "base_url" => "https://example.atlassian.net/wiki", "token_ref" => "env:CONFLUENCE_PAT" }.merge(confluence)
    )
    document["projects"] = projects || {
      "alpha" => {
        "name" => "Alpha",
        "jira_keys" => ["CLD"],
        "spaces" => ["CLD"],
        "style" => "scrum",
        "queries" => Marshal.load(Marshal.dump(JiraCld::ConfigStore::DEFAULT_QUERIES)),
        "team" => { "show_email" => false, "channels" => [] }
      }
    }
    store.save(document)
    store.path
  end

  def env(extra = {})
    {
      "CONFIG_PATH" => @config_path,
      "DATA_DIR" => @data_dir,
      "MCP_PROJECT_ID" => "alpha",
      "JIRA_API_TOKEN" => "test-token",
      "JIRA_EMAIL" => "dev@example.com",
      "CONFLUENCE_PAT" => "test-pat",
      "JIRA_BASE_URL" => "https://example.atlassian.net",
      "CACHE_ENABLED" => "1",
      "CACHE_SEARCH" => "0",
      "DB_AUTO_MIGRATE" => "1",
      "STATS_ENABLED" => "1"
    }.merge(extra)
  end

  def config(extra = {})
    JiraCld::Config.load(env: env(extra), config_path: @config_path)
  end

  def runtime(extra = {})
    cfg = config(extra)
    JiraCld::Runtime.build(config: cfg).tap { |value| JiraCld.runtime = value }
  end

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", name))
  end

  def json_fixture(name)
    JSON.parse(fixture(name))
  end
end
