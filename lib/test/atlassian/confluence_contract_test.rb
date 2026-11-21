# frozen_string_literal: true

require_relative "../test_helper"

class ConfluenceContractTest < CoreTest
  def setup
    super
    @config = config
    @client = JiraCore::HTTP::Client.new(base_url: @config.confluence_base_url)
    @confluence = JiraCore::Atlassian::Confluence.new(client: @client, config: @config)
  end

  def page_payload(id: "123", space: "CLD")
    {
      "id" => id,
      "title" => "Retry runbook",
      "spaceId" => "1",
      "version" => { "number" => 3, "when" => "2026-11-17T10:00:00.000Z",
                     "by" => { "displayName" => "Alice", "email" => "alice@example.com" } },
      "body" => { "view" => { "value" => "<p>Retry with backoff</p>", "representation" => "view" } },
      "_links" => { "base" => "https://example.atlassian.net/wiki", "webui" => "/spaces/#{space}/pages/#{id}" }
    }
  end

  def test_cloud_page_uses_v2_and_normalizes_body
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .with(query: { "body-format" => "view" })
      .to_return(status: 200, body: JSON.generate(page_payload), headers: { "Content-Type" => "application/json" })
    data = @confluence.page("123")
    compact = JiraCore::Serialize::Page.compact(data, base_url: @config.confluence_base_url)
    assert_equal "Retry runbook", compact["title"]
    assert_includes compact["body"], "Retry with backoff"
    assert_equal 3, compact["version"]
    assert_includes compact["url"], "/spaces/CLD/pages/123"
  end

  def test_cloud_page_falls_back_to_v1
    stub_request(:get, %r{https://example.atlassian.net/wiki/api/v2/pages/123}).to_return(status: 404)
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123")
      .with(query: hash_including("expand" => "body.view,version,space"))
      .to_return(status: 200, body: JSON.generate(page_payload), headers: { "Content-Type" => "application/json" })
    data = @confluence.page("123")
    assert_equal "Retry runbook", data["title"]
  end

  def test_space_post_filter
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content")
      .with(query: hash_including("title" => "Retry runbook"))
      .to_return(status: 200, body: JSON.generate({ "results" => [page_payload(space: "CLD")] }),
                 headers: { "Content-Type" => "application/json" })
    assert_equal "Retry runbook", @confluence.page_by_title("Retry runbook", "CLD")["title"]

    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content")
      .with(query: hash_including("title" => "Other"))
      .to_return(status: 200, body: JSON.generate({ "results" => [page_payload(space: "EVIL").merge("title" => "Other")] }),
                 headers: { "Content-Type" => "application/json" })
    assert_raises(JiraCore::Atlassian::Error) { @confluence.page_by_title("Other", "CLD") }
  end

  def test_cql_search
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/search")
      .with(query: hash_including("cql" => "space IN (\"CLD\") AND (text ~ \"retry\") ORDER BY lastmodified DESC"))
      .to_return(status: 200, body: JSON.generate({ "results" => [page_payload], "total" => 1, "start" => 0 }),
                 headers: { "Content-Type" => "application/json" })
    result = @confluence.search(cql: 'space IN ("CLD") AND (text ~ "retry") ORDER BY lastmodified DESC', limit: 10)
    assert_equal 1, result[:pages].length
    assert_nil result[:next_cursor]
  end

  def test_root_mounted_data_center_uses_root_rest_path
    cfg = config(confluence_base_url: "https://kb.example.com", deployment: "dc")
    client = JiraCore::HTTP::Client.new(base_url: cfg.confluence_base_url)
    confluence = JiraCore::Atlassian::Confluence.new(client: client, config: cfg)
    stub_request(:get, "https://kb.example.com/rest/api/space/CLD")
      .to_return(status: 200, body: JSON.generate({ "id" => "1", "key" => "CLD", "name" => "KB" }),
                 headers: { "Content-Type" => "application/json" })
    assert_equal "CLD", confluence.space("CLD")[:key]
  end

  def stub_page_scope(id = "123")
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/#{id}")
      .to_return(status: 200, body: JSON.generate(page_payload(id: id)),
                 headers: { "Content-Type" => "application/json" })
  end

  def test_page_history
    stub_page_scope
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/version")
      .with(query: hash_including("limit" => "2", "start" => "0"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [{ "number" => 3, "when" => "2026-11-17T10:00:00.000Z",
                                                                    "by" => { "displayName" => "Alice" },
                                                                    "message" => "fix typo" }],
                                                    "start" => 0, "total" => 1
                                                  }), headers: { "Content-Type" => "application/json" })

    result = @confluence.page_history("123", limit: 2)
    assert_equal 3, result[:versions].first["number"]
    assert_equal "Alice", result[:versions].first["author"]["display_name"]
    assert_nil result[:next_cursor]
  end

  def test_page_comments
    stub_page_scope
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/child/comment")
      .with(query: hash_including("expand" => "body.view,version"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [{
                                                      "id" => "c1", "title" => "Re: Retry",
                                                      "version" => { "when" => "2026-11-17T11:00:00.000Z",
                                                                     "by" => { "displayName" => "Bob" } },
                                                      "body" => { "view" => { "value" => "<p>Agreed</p>" } }
                                                    }], "start" => 0, "total" => 1
                                                  }), headers: { "Content-Type" => "application/json" })

    result = @confluence.page_comments("123")
    assert_equal "Agreed", result[:comments].first["body"]
    assert_equal "Bob", result[:comments].first["author"]["display_name"]
  end

  def test_labels_and_attachments
    stub_page_scope
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/label")
      .to_return(status: 200, body: JSON.generate({ "results" => [{ "id" => "1", "name" => "runbook", "prefix" => "global" }] }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/child/attachment")
      .with(query: hash_including("expand" => "version"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [{
                                                      "id" => "a1", "title" => "diagram.png",
                                                      "extensions" => { "mediaType" => "image/png", "fileSize" => 10 },
                                                      "_links" => { "download" => "/download/attachments/123/diagram.png" },
                                                      "version" => { "when" => "2026-11-17T10:00:00.000Z",
                                                                     "by" => { "displayName" => "Alice" } }
                                                    }], "start" => 0, "total" => 1
                                                  }), headers: { "Content-Type" => "application/json" })

    labels = @confluence.labels("123")
    assert_equal "runbook", labels[:labels].first["name"]

    attachments = @confluence.attachments("123")
    assert_equal "diagram.png", attachments[:attachments].first["filename"]
    assert_includes attachments[:attachments].first["download_url"], "/download/attachments/123/diagram.png"
  end

  def test_attachment_download
    stub_page_scope
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/child/attachment")
      .with(query: hash_including("limit" => "100"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [{ "id" => "a1", "title" => "diagram.png",
                                                                    "extensions" => { "mediaType" => "image/png", "fileSize" => 4 } }]
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/child/attachment/a1/download")
      .to_return(status: 200, body: "PNG!".b, headers: { "Content-Type" => "image/png" })

    result = @confluence.attachment("123", filename: "diagram.png")
    assert_equal "image/png", result[:mime_type]
    assert_equal "PNG!".b, result[:bytes]
  end

  def test_space_pages_rejects_out_of_scope_page
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content")
      .with(query: hash_including("spaceKey" => "CLD", "type" => "page"))
      .to_return(status: 200, body: JSON.generate({ "results" => [page_payload(space: "EVIL")], "total" => 1 }),
                 headers: { "Content-Type" => "application/json" })

    assert_raises(JiraCore::Atlassian::Error) { @confluence.space_pages("CLD") }
  end

  def test_space_resolve_is_cached
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/space/CLD")
      .to_return(status: 200, body: JSON.generate({ "id" => "1", "key" => "CLD", "name" => "Cloud" }),
                 headers: { "Content-Type" => "application/json" })
    reference = JiraCore::Repositories::Reference.new(cache: JiraCore::Cache::MemoryStore.new)
    confluence = JiraCore::Atlassian::Confluence.new(client: @client, config: @config, reference: reference)
    2.times { confluence.space("CLD") }
    assert_requested :get, "https://example.atlassian.net/wiki/rest/api/space/CLD", times: 1
  end
end
