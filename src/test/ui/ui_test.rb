# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"
require "jira_cld/ui/router"

class UITest < BaseTest
  def setup
    super
    write_config
    JiraCld::UI::Router.opts[:env] = env
    JiraCld::UI::Router.opts[:config_path] = @config_path
    JiraCld::UI::Router.opts[:theme] = "system"
    JiraCld::UI::Router.opts[:locale] = "ru"
    JiraCld::UI::Router.opts[:root] = JiraCld.root
    JiraCld::UI::Router.opts[:token] = "test-ui-token"
    @session = Rack::Test::Session.new(Rack::MockSession.new(JiraCld::UI::Router))
    @session.get "/?token=test-ui-token"
  end

  def test_ui_host_defaults_to_loopback_and_reads_env
    assert_equal "127.0.0.1", config.ui_host
    assert_equal "0.0.0.0", config("UI_HOST" => "0.0.0.0").ui_host
  end

  def test_requires_token
    fresh = Rack::Test::Session.new(Rack::MockSession.new(JiraCld::UI::Router))
    fresh.get "/projects"
    assert_equal 401, fresh.last_response.status
  end

  def test_overview_and_projects
    @session.get "/"
    assert_equal 200, @session.last_response.status
    assert_includes @session.last_response.body, "Alpha"
    @session.get "/projects"
    assert_includes @session.last_response.body, "Alpha"
  end

  def test_create_and_delete_project_soft
    @session.get "/projects/new"
    csrf = csrf_token
    @session.post "/projects", { id: "beta", name: "Beta", jira_keys: "BET", spaces: "BET_KB",
                                 style: "scrum", csrf: csrf }
    assert_equal 302, @session.last_response.status
    document = JiraCld::ConfigStore.new(path: @config_path).load
    assert document.dig("projects", "beta")

    @session.get "/projects/alpha/select"
    @session.post "/projects/beta/delete", { confirm: "beta", csrf: csrf }
    assert_equal 302, @session.last_response.status
    document = JiraCld::ConfigStore.new(path: @config_path).load
    assert_nil document.dig("projects", "beta")
    assert Dir.glob(File.join(@data_dir, ".trash", "beta-*")).any?
  end

  def test_cannot_delete_active_project
    @session.get "/projects/alpha/select"
    @session.get "/projects"
    csrf = csrf_token
    @session.post "/projects/alpha/delete", { confirm: "alpha", csrf: csrf }
    assert_equal 302, @session.last_response.status
    assert_includes @session.last_response["location"], "error="
    assert JiraCld::ConfigStore.new(path: @config_path).load.dig("projects", "alpha")
  end

  def test_csrf_is_required_for_mutations
    @session.post "/projects", { id: "beta", name: "Beta", jira_keys: "BET", spaces: "BET_KB" }
    assert_equal 403, @session.last_response.status
  end

  def test_cache_page_and_clear
    @session.get "/projects/alpha/cache"
    assert_equal 200, @session.last_response.status
    csrf = csrf_token
    @session.post "/projects/alpha/cache/clear", { scope: "expired", csrf: csrf }
    assert_equal 302, @session.last_response.status
  end

  def test_locale_and_theme_toggles
    @session.get "/locale/en?return_to=/projects"
    @session.get "/projects"
    assert_includes @session.last_response.body, "Projects"
    @session.get "/theme/dark?return_to=/projects"
    @session.get "/projects"
    assert_includes @session.last_response.body, 'data-theme="dark"'
  end

  def test_connections_masks_secrets
    @session.get "/connections"
    body = @session.last_response.body
    assert_includes body, "********"
    refute_includes body, "test-token"
  end

  private

  def csrf_token
    @session.last_response.body[/name="csrf" value="([^"]+)"/, 1] ||
      (@session.get("/projects/new") && @session.last_response.body[/name="csrf" value="([^"]+)"/, 1])
  end
end
