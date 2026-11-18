# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "timeout"
require "rbconfig"

class StdioIntegrationTest < BaseTest
  def test_ping_initialize_and_tools_list_are_pure_json_on_stdout
    write_config
    bin = File.expand_path("../../bin/jira-cld", __dir__)
    messages = [
      { jsonrpc: "2.0", id: 1, method: "initialize",
        params: { protocolVersion: "2025-11-25", capabilities: {},
                  clientInfo: { name: "test", version: "1" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "ping" },
      { jsonrpc: "2.0", id: 3, method: "tools/list" }
    ].map { |message| JSON.generate(message) }.join("\n") + "\n"

    out = err = nil
    status = nil
    Timeout.timeout(30) do
      Open3.popen3(env, RbConfig.ruby, bin, "mcp") do |stdin, stdout, stderr, wait|
        stdin.write(messages)
        stdin.close
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }
        out = stdout_reader.value
        err = stderr_reader.value
        status = wait.value
      end
    end

    assert status.success?, "process failed: #{err}"
    lines = out.lines.map(&:strip).reject(&:empty?)
    assert lines.length >= 3
    parsed = lines.map { |line| JSON.parse(line) }
    parsed.each { |message| assert_equal "2.0", message["jsonrpc"] }

    initialize_result = parsed.find { |message| message["id"] == 1 }["result"]
    assert_equal "2025-11-25", initialize_result["protocolVersion"]
    assert_equal "ruby-jira-mcp", initialize_result.dig("serverInfo", "name")

    tools = parsed.find { |message| message["id"] == 3 }.dig("result", "tools")
    assert_equal 19, tools.length
    assert_equal "private", parsed.find { |message| message["id"] == 3 }.dig("result", "cacheScope")

    refute_includes out, "mcp server starting"
    stderr_entries = err.lines.map(&:strip).reject(&:empty?)
    refute_empty stderr_entries
    stderr_entries.each { |line| JSON.parse(line) }
    assert_includes err, "mcp server starting"
  end

  def test_sigterm_exits_cleanly
    write_config
    bin = File.expand_path("../../bin/jira-cld", __dir__)
    status = nil
    Timeout.timeout(20) do
      Open3.popen3(env, RbConfig.ruby, bin, "mcp") do |stdin, stdout, stderr, wait|
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }
        sleep 2.0
        Process.kill("TERM", wait.pid)
        status = wait.value
        stdout_reader.join
        stderr_reader.join
        stdin.close
      end
    end
    assert_equal 0, status.exitstatus
  end

  def test_mcp_without_project_fails_closed
    write_config
    bin = File.expand_path("../../bin/jira-cld", __dir__)
    child_env = env("MCP_PROJECT_ID" => nil)
    out, err, status = Open3.capture3(child_env, RbConfig.ruby, bin, "mcp")
    refute status.success?
    assert_includes err, "MCP_PROJECT_ID is required"
    assert_empty out
  end
end
