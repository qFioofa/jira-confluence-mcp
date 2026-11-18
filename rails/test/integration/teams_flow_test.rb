# frozen_string_literal: true

require "test_helper"

class TeamsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "admin@example.com")
    @team = create_team(user: @user, slug: "alpha", name: "Alpha")
    sign_in
  end

  test "admin creates a connection, project and MCP endpoint" do
    post team_connections_path(@team), params: {
      connection: {
        provider: "jira",
        name: "Jira Cloud",
        base_url: "https://acme.atlassian.net",
        deployment: "cloud"
      }
    }
    assert_redirected_to team_connections_path(@team)
    connection = @team.connections.find_by!(name: "Jira Cloud")

    post team_projects_path(@team), params: {
      project: {
        name: "Alpha project",
        slug: "alpha-project",
        jira_connection_id: connection.id,
        jira_keys: "CLD, OPS",
        spaces: "CLD"
      }
    }
    project = @team.projects.find_by!(slug: "alpha-project")
    assert_redirected_to team_project_path(@team, project)
    assert_equal %w[CLD OPS], project.jira_keys
    assert_equal ["CLD"], project.spaces

    post mcp_endpoints_path, params: { project_id: project.id, name: "Personal" }
    assert_redirected_to mcp_endpoints_path
    assert flash[:mcp_token].present?
    assert @user.mcp_endpoints.exists?(project: project)
  end

  test "a user adds a personal credential" do
    connection = create_connection(team: @team)

    post user_credentials_path, params: {
      user_credential: {
        connection_id: connection.id,
        auth_type: "api_token",
        email: "admin@example.com",
        secret: "super-secret"
      }
    }

    assert_redirected_to user_credentials_path
    credential = @user.user_credentials.find_by!(connection: connection)
    assert_equal "super-secret", credential.secret
    assert_equal "super-secret".last(4), credential.secret_last4
  end

  test "a user cannot attach a credential to another team's connection" do
    other_user = create_user(email: "other@example.com")
    other_team = create_team(user: other_user, slug: "other", name: "Other")
    foreign = create_connection(team: other_team)

    post user_credentials_path, params: {
      user_credential: {
        connection_id: foreign.id,
        auth_type: "api_token",
        email: "admin@example.com",
        secret: "secret"
      }
    }

    assert_response :unprocessable_entity
    refute @user.user_credentials.exists?(connection: foreign)
  end

  private

  def sign_in
    post session_path, params: { email: @user.email, password: "password" }
  end
end
