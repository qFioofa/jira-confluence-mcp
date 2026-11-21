# frozen_string_literal: true

require_relative "../test_helper"

class IssuesRepositoryTest < CoreTest
  def setup
    super
    @config = config
    @runtime = JiraCore::Runtime.build(config: @config, cache: JiraCore::Cache::MemoryStore.new)
  end

  def issue(key = "CLD-1")
    {
      "id" => "1", "key" => key,
      "fields" => {
        "summary" => "Retry timeout",
        "status" => { "name" => "In Progress", "statusCategory" => { "name" => "In Progress" } },
        "issuetype" => { "name" => "Bug" },
        "assignee" => { "accountId" => "u1", "displayName" => "Alice" },
        "reporter" => { "accountId" => "u2", "displayName" => "Bob" },
        "updated" => "2026-11-17T10:00:00.000+0000",
        "created" => "2026-11-01T10:00:00.000+0000",
        "labels" => ["backend"],
        "components" => [{ "name" => "API" }],
        "description" => "Acceptance Criteria:\n- [ ] retries stop\n- [ ] logs include trace id\n"
      }
    }
  end

  def stub_search(issues: [issue], next_token: nil)
    body = { "issues" => issues, "nextPageToken" => next_token }.compact
    stub_request(:get, "https://example.atlassian.net/rest/api/3/search/jql")
      .with(query: hash_including("maxResults" => "2"))
      .to_return(status: 200, body: JSON.generate(body), headers: { "Content-Type" => "application/json" })
  end

  def test_search_issues_wraps_preset_and_returns_compact_dto
    stub_search
    result = @runtime.issues.search_issues(preset: "my_work", limit: 2)
    assert_equal 1, result["issues"].length
    assert_equal "CLD-1", result["issues"].first["key"]
    assert_equal "In Progress", result["issues"].first["status"]
    assert_includes result["issues"].first["url"], "/browse/CLD-1"
    assert_requested :get, %r{https://example.atlassian.net/rest/api/3/search/jql}, times: 1
  end

  def test_search_cache_enabled
    config = self.config(cache_search: true)
    runtime = JiraCore::Runtime.build(config: config, cache: JiraCore::Cache::MemoryStore.new)
    stub_search
    2.times { runtime.issues.search_issues(preset: "my_work", limit: 2) }
    assert_requested :get, %r{https://example.atlassian.net/rest/api/3/search/jql}, times: 1
  end

  def test_search_requires_exactly_one_selector
    assert_raises(JiraCore::Atlassian::QueryError) { @runtime.issues.search_issues }
    assert_raises(JiraCore::Atlassian::QueryError) do
      @runtime.issues.search_issues(jql: "status = Open", preset: "my_work")
    end
  end

  def test_unknown_preset
    error = assert_raises(JiraCore::Atlassian::QueryError) do
      @runtime.issues.search_issues(preset: "does_not_exist")
    end
    assert_equal :query_preset_unknown, error.query_code
  end

  def test_my_work_hints
    stub_search
    result = @runtime.issues.my_work(scope: "assigned", limit: 2)
    assert_equal "assigned", result["scope"]
    assert_includes result["issues"].first["why_now"], "assigned"
    refute_nil result["issues"].first["next_action"]
  end

  def test_my_work_uses_builtin_queries_without_presets
    registry = JiraCore::ProjectRegistry.new(
      [
        {
          "id" => "alpha",
          "name" => "Alpha",
          "jira_keys" => ["CLD"],
          "spaces" => ["CLD"],
          "queries" => { "jql" => {}, "cql" => {} }
        }
      ]
    )
    runtime = JiraCore::Runtime.build(config: config(registry: registry), cache: JiraCore::Cache::MemoryStore.new)
    stub_search

    result = runtime.issues.my_work(scope: "assigned", limit: 2)

    assert_equal "my_work", result["preset"]
    assert_equal "builtin", result["preset_source"]
    assert_equal 1, result["issues"].length
  end

  def test_get_issue_comments_and_changelog
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1")
      .with(query: hash_including("expand" => "renderedFields"))
      .to_return(status: 200, body: JSON.generate(issue), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1/comment})
      .to_return(status: 200, body: JSON.generate({ "comments" => [], "total" => 0 }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1/changelog})
      .to_return(status: 200, body: JSON.generate({ "values" => [], "total" => 0 }), headers: { "Content-Type" => "application/json" })
    result = @runtime.issues.get_issue("CLD-1", include: %w[comments changelog])
    assert result["issue"]
    assert_equal [], result["comments"]
    assert_equal [], result["changelog"]
  end

  def test_brief_extracts_acceptance_criteria_and_partial_warnings
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1(\?|$)})
      .to_return(status: 200, body: JSON.generate(issue), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1/comment})
      .to_return(status: 500, body: "{}")
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1/changelog})
      .to_return(status: 200, body: JSON.generate({ "values" => [] }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/search/jql})
      .to_return(status: 200, body: JSON.generate({ "issues" => [] }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/wiki/rest/api/content/search})
      .to_return(status: 500, body: "{}")

    result = @runtime.issues.brief("CLD-1", intent: "verify", depth: "standard")
    assert_equal ["retries stop", "logs include trace id"], result["acceptance_criteria"]
    assert_equal 2, result["acceptance_checklist"].length
    refute_empty result["warnings"]
  end
end
