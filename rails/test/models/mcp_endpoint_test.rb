# frozen_string_literal: true

require "test_helper"

class McpEndpointTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @team = create_team(user: @user)
    @jira = create_connection(team: @team)
    @project = create_project(team: @team, jira: @jira)
  end

  test "issues a token, authenticates it and revokes it" do
    endpoint = McpEndpoint.issue!(user: @user, project: @project, name: "Personal")
    token = endpoint.token

    assert token.present?
    assert_equal endpoint, McpEndpoint.authenticate(token)
    assert_equal token.first(8), endpoint.token_prefix
    refute_equal token, endpoint.token_digest

    endpoint.revoke!

    assert_nil McpEndpoint.authenticate(token)
  end

  test "rejects unknown tokens" do
    assert_nil McpEndpoint.authenticate("nope")
    assert_nil McpEndpoint.authenticate(nil)
  end
end
