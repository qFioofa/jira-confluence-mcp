# frozen_string_literal: true

require_relative "../test_helper"

class DiscoveryContractTest < CoreTest
  def setup
    super
    @config = config
    @client = JiraCore::HTTP::Client.new(base_url: @config.jira_base_url)
    @jira = JiraCore::Atlassian::Jira.new(client: @client, config: @config)
  end

  def issue(key = "CLD-1", links: nil)
    {
      "id" => "10001",
      "key" => key,
      "fields" => {
        "summary" => "Timeout on retry",
        "status" => { "name" => "In Progress" },
        "issuelinks" => links
      }.compact
    }
  end

  def test_boards_supports_filters_and_cursor
    stub_request(:get, "https://example.atlassian.net/rest/agile/1.0/board")
      .with(query: hash_including("projectKeyOrId" => "CLD", "maxResults" => "1"))
      .to_return(status: 200, body: JSON.generate({
                                                    "values" => [{ "id" => 7, "name" => "CLD board", "type" => "scrum",
                                                                   "location" => { "projectKey" => "CLD" } }],
                                                    "total" => 2
                                                  }), headers: { "Content-Type" => "application/json" })

    result = @jira.boards(project_key: "CLD", limit: 1)
    assert_equal "CLD board", result[:boards].first[:name]
    decoded = JiraCore::Atlassian::Cursor.decode(result[:next_cursor])
    assert_equal 1, decoded[:s]
  end

  def test_fields_filter_by_name_and_custom
    stub_request(:get, "https://example.atlassian.net/rest/api/3/field")
      .to_return(status: 200, body: JSON.generate([
                                                    { "id" => "summary", "name" => "Summary", "custom" => false,
                                                      "schema" => { "type" => "string", "system" => "summary" },
                                                      "clauseNames" => ["summary"] },
                                                    { "id" => "customfield_1", "name" => "Story Points", "custom" => true,
                                                      "schema" => { "type" => "number" } }
                                                  ]), headers: { "Content-Type" => "application/json" })

    all = @jira.fields
    assert_equal 2, all[:total]
    custom = @jira.fields(custom: true)
    assert_equal 1, custom[:total]
    assert_equal "customfield_1", custom[:fields].first[:id]
    assert_equal 1, @jira.fields(query: "story")[:total]
  end

  def test_transitions_expose_required_fields
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1/transitions")
      .with(query: hash_including("expand" => "transitions.fields"))
      .to_return(status: 200, body: JSON.generate({
                                                    "transitions" => [{
                                                      "id" => "11", "name" => "Start Progress", "to" => { "id" => "3", "name" => "In Progress" },
                                                      "hasScreen" => true,
                                                      "fields" => {
                                                        "assignee" => { "name" => "Assignee", "required" => true,
                                                                        "schema" => { "type" => "user" } }
                                                      }
                                                    }]
                                                  }), headers: { "Content-Type" => "application/json" })

    result = @jira.transitions("CLD-1")
    assert_equal "Start Progress", result[:transitions].first[:name]
    assert_equal "assignee", result[:transitions].first[:required_fields].first[:id]
  end

  def test_transitions_reject_out_of_scope_key
    error = assert_raises(JiraCore::Atlassian::Error) { @jira.transitions("EVIL-1") }
    assert_equal :scope_forbidden, error.code
  end

  def test_search_users_uses_query_on_cloud
    stub_request(:get, "https://example.atlassian.net/rest/api/3/user/search")
      .with(query: hash_including("query" => "Ali", "maxResults" => "10"))
      .to_return(status: 200, body: JSON.generate([{ "accountId" => "u1", "displayName" => "Alice",
                                                     "emailAddress" => "alice@example.com" }]),
                 headers: { "Content-Type" => "application/json" })

    result = @jira.search_users("Ali", limit: 10)
    assert_equal "Alice", result[:users].first["display_name"]
    assert_nil result[:users].first["email"]
  end

  def test_worklogs_render_adf_comment
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1/worklog")
      .with(query: hash_including("startAt" => "0", "maxResults" => "50"))
      .to_return(status: 200, body: JSON.generate({
                                                    "worklogs" => [{
                                                      "id" => "w1", "author" => { "displayName" => "Alice" },
                                                      "timeSpent" => "1h", "timeSpentSeconds" => 3600,
                                                      "started" => "2026-11-17T10:00:00.000+0000",
                                                      "comment" => { "type" => "doc", "content" => [
                                                        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "investigation" }] }
                                                      ] }
                                                    }], "startAt" => 0, "total" => 1
                                                  }), headers: { "Content-Type" => "application/json" })

    result = @jira.worklogs("CLD-1")
    assert_equal "investigation", result[:worklogs].first["comment"]
    assert_nil result[:next_cursor]
  end

  def test_link_types_and_project_versions
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issueLinkType")
      .to_return(status: 200, body: JSON.generate({
                                                    "issueLinkTypes" => [{ "id" => "1", "name" => "Blocks", "inward" => "is blocked by",
                                                                           "outward" => "blocks" }]
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/rest/api/3/project/CLD/versions")
      .to_return(status: 200, body: JSON.generate([{ "id" => "v1", "name" => "1.0", "released" => false,
                                                     "releaseDate" => "2026-12-01" }]),
                 headers: { "Content-Type" => "application/json" })

    types = @jira.issue_link_types(name_filter: "block")
    assert_equal "Blocks", types[:link_types].first[:name]

    versions = @jira.project_versions("CLD")
    assert_equal "1.0", versions[:versions].first[:name]
    assert_equal "2026-12-01", versions[:versions].first[:release_date]
  end

  def test_attachment_returns_bytes
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1")
      .with(query: hash_including("fields" => "attachment,summary"))
      .to_return(status: 200, body: JSON.generate(issue.merge(
                                                    "fields" => {
                                                      "summary" => "Timeout",
                                                      "attachment" => [{ "id" => "a1", "filename" => "shot.png",
                                                                         "mimeType" => "image/png", "size" => 4,
                                                                         "content" => "https://example.atlassian.net/secure/attachment/1/shot.png" }]
                                                    }
                                                  )), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/secure/attachment/1/shot.png")
      .to_return(status: 200, body: "\x89PNG".b, headers: { "Content-Type" => "image/png" })

    result = @jira.attachment("CLD-1", filename: "shot.png")
    assert_equal "image/png", result[:mime_type]
    assert_equal "\x89PNG".b, result[:bytes]
    assert result[:inline]
  end
end
