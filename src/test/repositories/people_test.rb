# frozen_string_literal: true

require_relative "../test_helper"

class PeopleRepositoryTest < BaseTest
  def setup
    super
    write_config
    @runtime = JiraCld::Runtime.build(config: config)
    JiraCld.runtime = @runtime
  end

  def issue
    {
      "id" => "1", "key" => "CLD-1",
      "fields" => {
        "summary" => "Retry timeout",
        "status" => { "name" => "In Progress", "statusCategory" => { "name" => "In Progress" } },
        "assignee" => { "accountId" => "u1", "displayName" => "Alice", "emailAddress" => "alice@example.com" },
        "reporter" => { "accountId" => "bot1", "displayName" => "Deploy Bot", "accountType" => "bot" },
        "updated" => "2026-11-17T10:00:00.000+0000",
        "labels" => ["backend"]
      }
    }
  end

  def test_who_knows_excludes_bots_and_hides_email
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/search/jql})
      .to_return(status: 200, body: JSON.generate({ "issues" => [issue] }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/wiki/rest/api/content/search})
      .to_return(status: 200, body: JSON.generate({ "results" => [], "total" => 0 }),
                 headers: { "Content-Type" => "application/json" })

    result = @runtime.people.who_knows(topic: "retry", window: 30, limit: 5)
    names = result["people"].map { |person| person["display_name"] }
    assert_includes names, "Alice"
    refute_includes names, "Deploy Bot"
    alice = result["people"].find { |person| person["display_name"] == "Alice" }
    assert_nil alice["email"]
    assert_includes %w[low medium high], alice["confidence"]
    refute_empty result["gaps"]
  end

  def test_prepare_question_returns_packet_without_sending
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/issue/CLD-1})
      .to_return(status: 200, body: JSON.generate(issue), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/rest/api/3/search/jql})
      .to_return(status: 200, body: JSON.generate({ "issues" => [issue] }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://example.atlassian.net/wiki/rest/api/content/search})
      .to_return(status: 200, body: JSON.generate({ "results" => [], "total" => 0 }),
                 headers: { "Content-Type" => "application/json" })

    packet = @runtime.people.prepare_question(issue_key: "CLD-1", goal: "fix retries", urgency: "high")
    assert_equal false, packet["sent"]
    assert_nil packet["requested_via"]
    assert_operator packet["questions"].length, :>=, 3
    assert_operator packet["questions"].length, :<=, 5
    assert(packet["questions"].all? { |question| question["reason"] })
    assert_equal "high", packet["urgent"]
  end
end
