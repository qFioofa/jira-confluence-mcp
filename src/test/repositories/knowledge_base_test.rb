# frozen_string_literal: true

require_relative "../test_helper"

class KnowledgeBaseRepositoryTest < BaseTest
  def setup
    super
    write_config
    @runtime = JiraCld::Runtime.build(config: config)
    JiraCld.runtime = @runtime
  end

  def page(version:, text:)
    {
      "id" => "123",
      "title" => "Retry runbook",
      "version" => { "number" => version, "when" => "2026-11-17T10:00:00.000Z",
                     "by" => { "displayName" => "Alice" } },
      "body" => { "view" => { "value" => "<p>#{text}</p>", "representation" => "view" } },
      "_links" => { "base" => "https://example.atlassian.net/wiki",
                    "webui" => "/spaces/CLD/pages/123" }
    }
  end

  def test_page_is_cached_and_versioned
    meta_v3 = page(version: 3, text: "ignored")
    meta_v3["body"] = nil
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .with(query: { "body-format" => "view" })
      .to_return(status: 200, body: JSON.generate(page(version: 3, text: "v3")),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .with(query: {})
      .to_return(status: 200, body: JSON.generate(meta_v3), headers: { "Content-Type" => "application/json" })

    first = @runtime.knowledge_base.get_page(id: "123")["page"]
    assert_equal "Retry runbook", first["title"]
    assert_includes first["body"], "v3"
    assert_equal 3, first["version"]

    @runtime.knowledge_base.get_page(id: "123")
    assert_requested :get, %r{https://example.atlassian.net/wiki/api/v2/pages/123}, times: 2

    meta_v4 = page(version: 4, text: "ignored")
    meta_v4["body"] = nil
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .with(query: {})
      .to_return(status: 200, body: JSON.generate(meta_v4), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .with(query: { "body-format" => "view" })
      .to_return(status: 200, body: JSON.generate(page(version: 4, text: "v4")),
                 headers: { "Content-Type" => "application/json" })
    @runtime.cache.delete(ns: "page_meta", logical: { id: "123" })
    second = @runtime.knowledge_base.get_page(id: "123")["page"]
    assert_equal 4, second["version"]
    assert_includes second["body"], "v4"
  end

  def test_cql_search_is_bounded
    stub_request(:get, %r{https://example.atlassian.net/wiki/rest/api/content/search})
      .with(query: hash_including("cql" => 'space IN ("CLD") AND ((text ~ "retry")) ORDER BY lastmodified DESC'))
      .to_return(status: 200, body: JSON.generate({ "results" => [page(version: 3, text: "v3")], "total" => 1 }),
                 headers: { "Content-Type" => "application/json" })
    result = @runtime.knowledge_base.search(query: "retry", limit: 5)
    assert_equal 1, result["pages"].length
    assert_equal "Retry runbook", result["pages"].first["title"]
  end
end
