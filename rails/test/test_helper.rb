ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # SQLite is a single-writer database; keep the suite deterministic locally.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def create_user(email: "user@example.com", password: "password", admin: false)
      User.create!(email: email, password: password, name: "User", admin: admin)
    end

    def create_team(user:, slug: "alpha", name: "Alpha")
      team = Team.create!(slug: slug, name: name)
      Membership.create!(team: team, user: user, role: "admin")
      team
    end

    def create_connection(team:, provider: "jira", name: nil, base_url: nil)
      Connection.create!(
        team: team,
        provider: provider,
        name: name || provider.capitalize,
        base_url: base_url || "https://#{provider}.example.test"
      )
    end

    def create_project(team:, jira:, slug: "alpha-project", name: "Alpha project", confluence: nil)
      Project.create!(
        team: team,
        slug: slug,
        name: name,
        jira_connection: jira,
        confluence_connection: confluence,
        jira_keys: ["CLD"],
        spaces: confluence ? ["CLD"] : []
      )
    end

    def create_credential(user:, connection:, secret: "test-token", email: "user@example.com", auth_type: "api_token")
      credential = UserCredential.new(user: user, connection: connection, auth_type: auth_type, email: email)
      credential.secret = secret
      credential.save!
      credential
    end
  end
end
