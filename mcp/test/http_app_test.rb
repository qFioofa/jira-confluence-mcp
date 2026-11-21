# frozen_string_literal: true

require_relative "test_helper"
require "rack/mock"
require "stringio"

class HTTPAppTest < McpTest
  def setup
    super
    @log = StringIO.new
    logger = JiraMcp::LocalRuntime::LogSink.new(io: @log)
    @app = JiraMcp::HTTPApp.new(runtime: runtime, logger: logger)
    @request = Rack::MockRequest.new(@app)
  end

  def test_health
    response = @request.get("/health")

    assert_equal 200, response.status
    assert_equal "application/json", response.headers["content-type"]
    assert_equal({ "status" => "ok", "project" => "alpha" }, JSON.parse(response.body))
  end

  def test_initialize
    response = post_mcp(initialize_payload)

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal "2025-11-25", body.dig("result", "protocolVersion")
    assert_equal "jira-web", body.dig("result", "serverInfo", "name")
  end

  def test_tools_list
    response = post_mcp(jsonrpc: "2.0", id: 2, method: "tools/list")

    assert_equal 200, response.status
    tools = JSON.parse(response.body).dig("result", "tools")
    assert_equal 41, tools.length
    assert_includes tools.map { |tool| tool["name"] }, "jira_search_issues"
    assert_includes tools.map { |tool| tool["name"] }, "jira_list_boards"
    assert_includes tools.map { |tool| tool["name"] }, "kb_space_tree"
  end

  def test_rejects_unknown_path
    response = @request.get("/nope")

    assert_equal 404, response.status
  end

  def test_normalizes_path
    assert_equal "/mcp", JiraMcp::HTTPApp.normalize_path("mcp")
    assert_equal "/mcp", JiraMcp::HTTPApp.normalize_path("/mcp/")
    assert_equal "/", JiraMcp::HTTPApp.normalize_path("")
  end

  private

  def post_mcp(payload)
    @request.post(
      "/mcp",
      input: JSON.generate(payload),
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25",
      "HTTP_HOST" => "127.0.0.1"
    )
  end

  def initialize_payload
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-11-25",
        capabilities: {},
        clientInfo: { name: "test", version: "1" }
      }
    }
  end
end
