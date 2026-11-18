# frozen_string_literal: true

require_relative "../test_helper"

class JiraContractTest < CoreTest
  def setup
    super
    @config = config
    @client = JiraCore::HTTP::Client.new(base_url: @config.jira_base_url)
    @jira = JiraCore::Atlassian::Jira.new(client: @client, config: @config)
  end

  def cloud_issue(key = "CLD-1")
    {
      "id" => "10001",
      "key" => key,
      "fields" => {
        "summary" => "Timeout on retry",
        "status" => { "name" => "In Progress", "statusCategory" => { "name" => "In Progress" } },
        "issuetype" => { "name" => "Bug" },
        "priority" => { "name" => "High" },
        "assignee" => { "accountId" => "u1", "displayName" => "Alice", "emailAddress" => "alice@example.com" },
        "reporter" => { "accountId" => "u2", "displayName" => "Bob" },
        "updated" => "2026-11-17T10:00:00.000+0000",
        "created" => "2026-11-01T10:00:00.000+0000",
        "labels" => ["backend"],
        "components" => [{ "name" => "API" }],
        "description" => { "type" => "doc",
                           "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Description" }] }] }
      }
    }
  end

  def test_cloud_search_uses_jql_endpoint_and_next_page_token
    stub_request(:get, "https://example.atlassian.net/rest/api/3/search/jql")
      .with(query: hash_including("maxResults" => "2", "jql" => "project IN (CLD) AND (text ~ \"timeout\") ORDER BY updated DESC"))
      .to_return(status: 200, body: JSON.generate({ "issues" => [cloud_issue], "nextPageToken" => "next-token" }),
                 headers: { "Content-Type" => "application/json" })

    result = @jira.search(jql: 'project IN (CLD) AND (text ~ "timeout") ORDER BY updated DESC', limit: 2)
    assert_equal 1, result[:issues].length
    refute_nil result[:next_cursor]
    decoded = JiraCore::Atlassian::Cursor.decode(result[:next_cursor])
    assert_equal "next-token", decoded[:t]
  end

  def test_cloud_auth_is_basic
    stub_request(:get, "https://example.atlassian.net/rest/api/3/myself")
      .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("dev@example.com:test-token")}" })
      .to_return(status: 200, body: JSON.generate({ "accountId" => "u1", "displayName" => "Dev" }))
    assert_equal "Dev", @jira.myself["displayName"]
  end

  def test_post_filter_rejects_outside_allowlist
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/search/jql})
      .to_return(status: 200, body: JSON.generate({ "issues" => [cloud_issue("EVIL-1")] }),
                 headers: { "Content-Type" => "application/json" })
    error = assert_raises(JiraCore::Atlassian::Error) do
      @jira.search(jql: "project IN (CLD)", limit: 2)
    end
    assert_equal :scope_forbidden, error.code
  end

  def test_error_mapping_401
    stub_request(:get, "https://example.atlassian.net/rest/api/3/myself")
      .to_return(status: 401, body: JSON.generate({ "errorMessages" => ["Unauthorized"] }))
    error = assert_raises(JiraCore::Atlassian::AuthError) { @jira.myself }
    assert_equal :auth_failed, error.code
    assert_includes error.hint, "JIRA_EMAIL"
  end

  def test_dc_search_uses_start_at_and_bearer
    config = self.config(deployment: "dc", jira_pat: "dc-pat", jira_api_token: nil)
    client = JiraCore::HTTP::Client.new(base_url: config.jira_base_url)
    jira = JiraCore::Atlassian::Jira.new(client: client, config: config)
    stub_request(:get, "https://example.atlassian.net/rest/api/2/search")
      .with(query: hash_including("startAt" => "0"), headers: { "Authorization" => "Bearer dc-pat" })
      .to_return(status: 200, body: JSON.generate({ "issues" => [cloud_issue], "total" => 3, "startAt" => 0 }),
                 headers: { "Content-Type" => "application/json" })

    result = jira.search(jql: "project IN (CLD)", limit: 1)
    assert_equal 1, result[:issues].length
    decoded = JiraCore::Atlassian::Cursor.decode(result[:next_cursor])
    assert_equal 1, decoded[:s]
    assert_equal "dc", result[:deployment]
  end

  def test_comments_and_changelog_mapping
    comment_body = {
      "type" => "doc",
      "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Looks good" }] }]
    }
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1/comment})
      .to_return(status: 200, body: JSON.generate({
                                                    "comments" => [{ "id" => "c1", "author" => { "displayName" => "Alice" },
                                                                     "body" => comment_body,
                                                                     "created" => "2026-11-17T10:00:00.000+0000" }],
                                                    "total" => 1, "startAt" => 0
                                                  }), headers: { "Content-Type" => "application/json" })
    result = @jira.comments("CLD-1", limit: 10)
    assert_equal 1, result[:comments].length
    assert_equal "Alice", result[:comments].first["author"]["display_name"]
    assert_nil result[:comments].first["author"]["email"]
  end

  def test_attachment_metadata_only
    issue = cloud_issue
    issue["fields"]["attachment"] = [{ "id" => "a1", "filename" => "run.log", "size" => 10,
                                       "mimeType" => "text/plain", "content" => "https://example/run.log" }]
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1")
      .with(query: hash_including("fields" => "attachment,summary,updated"))
      .to_return(status: 200, body: JSON.generate(issue), headers: { "Content-Type" => "application/json" })
    result = @jira.attachments("CLD-1")
    assert_equal "run.log", result[:attachments].first["filename"]
    refute result[:attachments].first.key?("data")
  end
end
