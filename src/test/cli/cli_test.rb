# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "jira_cld/cli/setup"
require "jira_cld/cli/doctor"
require "jira_cld/cli/stats_command"
require "jira_cld/cli/cache_command"
require "jira_cld/cli/projects"
require "jira_cld/cli/config_command"
require "jira_cld/cli/export"

class CLITest < BaseTest
  def test_setup_non_interactive_dry_run_writes_nothing
    args = %w[--non-interactive --dry-run --jira-url https://acme.atlassian.net
              --deployment cloud --email dev@acme.io --token-ref env:JIRA_API_TOKEN
              --space ALP_KB --project alpha --jira-key ALP --locale ru]
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::Setup.new(args, env: env).run
    end
    assert_includes out, "dry-run"
    refute File.exist?(@config_path)
  end

  def test_setup_non_interactive_writes_valid_config
    args = %w[--non-interactive --jira-url https://acme.atlassian.net
              --deployment cloud --email dev@acme.io --token-ref env:JIRA_API_TOKEN
              --space ALP_KB --project alpha --jira-key ALP --locale ru]
    capture_io do
      assert_equal 0, JiraCld::CLI::Setup.new(args, env: env).run
    end
    assert File.exist?(@config_path)
    assert_equal 0o600, File.stat(@config_path).mode & 0o777
    document = JiraCld::ConfigStore.new(path: @config_path).load
    assert_equal ["ALP"], document.dig("projects", "alpha", "jira_keys")
    assert_equal ["ALP_KB"], document.dig("projects", "alpha", "spaces")
    assert File.directory?(File.join(@data_dir, "alpha"))
  end

  def test_doctor_offline
    write_config
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::Doctor.new(["--offline", "--project", "alpha"], env: env).run
    end
    assert_includes out, "[ok] config"
    assert_includes out, "[ok] secrets"
  end

  def test_stats_json
    write_config
    cfg = config
    JiraCld::DB.setup!(cfg)
    writer = JiraCld::Stats::Writer.new(cfg)
    writer.record_tool(tool: "jira_get_issue", outcome: "ok", duration_ms: 12.5)
    writer.record_cache(hit: true, namespace: "issue")
    writer.flush!
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::StatsCommand.new(["--json", "--project", "alpha"], env: env).run
    end
    payload = JSON.parse(out)
    assert_equal 1, payload.dig("summary", "requests")
    assert_equal 100.0, payload.dig("summary", "hit_rate")
  end

  def test_cache_clear_requires_yes
    write_config
    assert_equal 2, JiraCld::CLI::CacheCommand.new(%w[clear --project alpha], env: env).run
  end

  def test_cache_clear_with_yes
    write_config
    cfg = config
    JiraCld::DB.setup!(cfg)
    store = JiraCld::Cache::DatabaseStore.new(max_bytes: cfg.cache_max_bytes, stale_grace: 0,
                                              max_entry_bytes: cfg.cache_max_entry_bytes)
    key = JiraCld::Cache::Key.build(project: "alpha", site: "s", principal: "p", ns: "issue", logical: 1)
    store.write_record(key, { "v" => 1 }, ns: "issue", ttl: 60)
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::CacheCommand.new(%w[clear --project alpha --scope all --yes], env: env).run
    end
    assert_includes out, "cache cleared"
    assert_nil store.read_record(key)
  end

  def test_projects_remove_requires_yes_and_soft_deletes
    write_config
    Dir.mkdir(@data_dir) unless Dir.exist?(@data_dir)
    beta_dir = File.join(@data_dir, "beta")
    FileUtils.mkdir_p(beta_dir)
    File.write(File.join(beta_dir, "cache.db"), "x")
    registry = JiraCld::ConfigStore.new(path: @config_path).tap do |store|
      doc = store.load
      doc["projects"]["beta"] = { "name" => "Beta", "jira_keys" => ["BET"], "spaces" => ["BET_KB"],
                                  "queries" => Marshal.load(Marshal.dump(JiraCld::ConfigStore::DEFAULT_QUERIES)) }
      store.save(doc)
    end
    assert_equal 2, JiraCld::CLI::Projects.new(%w[remove --project beta], env: env).run
    capture_io do
      assert_equal 0, JiraCld::CLI::Projects.new(%w[remove --project beta --yes], env: env).run
    end
    refute Dir.exist?(beta_dir)
    assert Dir.glob(File.join(@data_dir, ".trash", "beta-*")).any?
    assert_nil registry.load["projects"]["beta"]
  end

  def test_print_opencode_does_not_leak_token
    write_config
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::ConfigCommand.new(%w[print-opencode], env: env).run
    end
    assert_includes out, "MCP_PROJECT_ID"
    assert_includes out, "{env:JIRA_API_TOKEN}"
    refute_includes out, "test-token"
  end

  def test_print_opencode_http_uses_url_without_token
    write_config
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::ConfigCommand.new(
        %w[print-opencode --http --port 8765 --path /mcp --project alpha], env: env
      ).run
    end
    payload = JSON.parse(out)
    entry = payload.dig("mcp", "servers", "jira-alpha")
    assert_equal "remote", entry["type"]
    assert_equal "http://127.0.0.1:8765/mcp", entry["url"]
    refute entry.key?("environment")
    refute_includes out, "test-token"
  end

  def test_print_opencode_http_works_from_binary
    write_config
    bin = File.expand_path("../../bin/jira-cld", __dir__)
    out, err, status = Open3.capture3(
      env, RbConfig.ruby, bin, "config", "print-opencode", "--http", "--port", "8765", "--project", "alpha"
    )
    assert status.success?, err
    entry = JSON.parse(out).dig("mcp", "servers", "jira-alpha")
    assert_equal "remote", entry["type"]
    assert_equal "http://127.0.0.1:8765/mcp", entry["url"]
    refute_includes out, "test-token"
  end

  def test_export_redacts_secrets
    write_config
    out, = capture_io do
      assert_equal 0, JiraCld::CLI::Export.new(%w[diagnostics], env: env).run
    end
    payload = JSON.parse(out)
    assert_equal "0.1.0", payload["version"]
    refute_includes out, "test-token"
  end
end
