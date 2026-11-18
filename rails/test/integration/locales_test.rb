# frozen_string_literal: true

require "test_helper"

class LocalesTest < ActionDispatch::IntegrationTest
  setup do
    user = create_user
    create_team(user: user)
    post session_path, params: { email: user.email, password: "password" }
  end

  test "switches the interface to Russian" do
    get set_locale_path("ru")

    assert_redirected_to root_path

    get root_path

    assert_includes response.body, "Дашборд"
  end

  test "switches the interface back to English" do
    get set_locale_path("ru")
    get set_locale_path("en")

    get root_path

    assert_includes response.body, "Dashboard"
  end
end
