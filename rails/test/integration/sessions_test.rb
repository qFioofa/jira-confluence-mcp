# frozen_string_literal: true

require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "admin@example.com")
    @team = create_team(user: @user)
    @jira = create_connection(team: @team)
    @project = create_project(team: @team, jira: @jira)
  end

  test "requires login for the dashboard" do
    get root_path

    assert_redirected_to login_path
  end

  test "signs in and shows the dashboard" do
    post session_path, params: { email: @user.email, password: "password" }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Dashboard"
    assert_includes response.body, "Alpha project"
  end

  test "rejects invalid credentials" do
    post session_path, params: { email: @user.email, password: "wrong" }

    assert_response :unprocessable_entity
    assert_includes response.body, "Invalid email or password"
  end
end
