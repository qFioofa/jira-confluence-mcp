# frozen_string_literal: true

require_relative "../test_helper"
require "rack/mock"

class HttpIntegrationTest < BaseTest
  def setup
    super
    write_config
    @runtime = JiraCld::Runtime.build(config: config)
    JiraCld.runtime = @runtime
    @server = JiraCld::Server.build(config: config, runtime: @runtime)
  end

  def test_initialize_and_tools_list_over_http
    app = @server.http_app(path: "/mcp", stateless: true, enable_json_response: true)

    response = post(app, "/mcp", initialize_message)
    assert_equal 200, response.status
    payload = JSON.parse(response.body)
    assert_equal "2025-11-25", payload.dig("result", "protocolVersion")
    assert_equal "ruby-jira-mcp", payload.dig("result", "serverInfo", "name")

    response = post(app, "/mcp", tools_list_message)
    assert_equal 200, response.status
    payload = JSON.parse(response.body)
    assert_equal 19, payload.dig("result", "tools").length
  end

  def test_health_endpoint_returns_project
    app = @server.http_app(path: "/mcp", stateless: true)
    response = Rack::MockRequest.new(app).get("/health", "HTTP_HOST" => "127.0.0.1:8765")
    assert_equal 200, response.status
    assert_equal "alpha", JSON.parse(response.body)["project"]
  end

  def test_unknown_path_returns_404
    app = @server.http_app(path: "/mcp", stateless: true)
    response = Rack::MockRequest.new(app).get("/nope", "HTTP_HOST" => "127.0.0.1:8765")
    assert_equal 404, response.status
  end

  def test_dns_rebinding_protection_rejects_foreign_host
    app = @server.http_app(path: "/mcp", stateless: true, enable_json_response: true)
    response = post(app, "/mcp", initialize_message, host: "evil.example:8765")
    assert_equal 403, response.status
  end

  def test_allowed_hosts_can_be_extended
    app = @server.http_app(path: "/mcp", stateless: true, enable_json_response: true,
                           allowed_hosts: ["jira.internal:8765"])
    response = post(app, "/mcp", initialize_message, host: "jira.internal:8765")
    assert_equal 200, response.status
  end

  private

  def post(app, path, message, host: "127.0.0.1:8765")
    Rack::MockRequest.new(app).post(
      path,
      "HTTP_HOST" => host,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25",
      input: JSON.generate(message)
    )
  end

  def initialize_message
    {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-11-25", capabilities: {},
                clientInfo: { name: "test", version: "1" } }
    }
  end

  def tools_list_message
    { jsonrpc: "2.0", id: 2, method: "tools/list" }
  end
end
