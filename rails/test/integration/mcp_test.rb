# frozen_string_literal: true

require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @team = create_team(user: @user)
    @jira = create_connection(team: @team)
    @confluence = create_connection(
      team: @team,
      provider: "confluence",
      base_url: "https://jira.example.test/wiki"
    )
    @project = create_project(team: @team, jira: @jira, confluence: @confluence)
    create_credential(user: @user, connection: @jira)
    create_credential(user: @user, connection: @confluence)
    @endpoint = McpEndpoint.issue!(user: @user, project: @project, name: "Personal")
  end

  test "initialize and tools/list work over the HTTP transport" do
    post_mcp(initialize_payload)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "2025-11-25", body.dig("result", "protocolVersion")
    assert_equal "jira-web", body.dig("result", "serverInfo", "name")

    post_mcp({ jsonrpc: "2.0", id: 2, method: "tools/list" })

    assert_response :success
    tools = JSON.parse(response.body).dig("result", "tools")
    assert_equal 19, tools.length
    assert_includes tools.map { |tool| tool["name"] }, "jira_search_issues"
  end

  test "project_list returns the bound project" do
    post_mcp(
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: { name: "project_list", arguments: {} }
    )

    assert_response :success
    body = JSON.parse(response.body)
    refute body.dig("result", "isError")
    payload = JSON.parse(body.dig("result", "content", 0, "text"))
    assert_equal "alpha-project", payload["bound_project"]
    assert_equal ["alpha-project"], payload["projects"].map { |project| project["id"] }
  end

  test "rejects unknown tokens" do
    post "/mcp/nope", params: JSON.generate(initialize_payload), headers: mcp_headers

    assert_response :unauthorized
    assert_equal "invalid or revoked MCP token", JSON.parse(response.body).dig("error", "message")
  end

  test "returns a structured error when the user credential is missing" do
    assert @endpoint.update_columns(revoked_at: nil)
    @user.user_credentials.find_by(connection: @jira).destroy!

    post_mcp(initialize_payload)

    assert_response :forbidden
    error = JSON.parse(response.body).dig("error")
    assert_equal "user_credential_missing", error.dig("data", "code")
    assert_equal "/user_credentials/new", error.dig("data", "connect_url")
  end

  private

  def post_mcp(payload)
    post "/mcp/#{@endpoint.token}", params: JSON.generate(payload), headers: mcp_headers
  end

  def mcp_headers
    {
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json, text/event-stream",
      "MCP-PROTOCOL-VERSION" => "2025-11-25",
      "HOST" => "127.0.0.1"
    }
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
