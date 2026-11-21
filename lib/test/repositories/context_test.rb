# frozen_string_literal: true

require_relative "../test_helper"

class ContextTest < CoreTest
  FakeIssues = Struct.new(:brief_data) do
    def brief(*, **)
      brief_data
    end
  end

  FakeKnowledgeBase = Struct.new(:pages) do
    def enabled?
      true
    end

    def search(*, **)
      { "pages" => pages }
    end
  end

  FakePeople = Struct.new(:people) do
    def who_knows(*, **)
      { "people" => people, "gaps" => [], "warnings" => [] }
    end
  end

  FakeGit = Struct.new(:commits_data, :experts_data) do
    def enabled?
      true
    end

    def find_issue_refs(*, **)
      { "commits" => commits_data, "branches" => [], "repositories" => ["backend"], "warnings" => [] }
    end

    def experts(*, **)
      { "experts" => experts_data, "bus_factor" => { "top1_share" => 0.7,
                                                     "note" => "high concentration: one author accounts for 70% of changes" },
        "repositories" => ["backend"], "gaps" => [], "warnings" => [] }
    end
  end

  def issue
    {
      "key" => "CLD-1",
      "id" => "10001",
      "summary" => "Add retry to the checkout API",
      "status" => "In Progress",
      "type" => "Story",
      "priority" => "High",
      "description" => "We need to add retries to the checkout API.\n\nOut of scope: billing changes.",
      "assignee" => { "account_id" => "u1", "display_name" => "Alice" },
      "components" => ["API"],
      "labels" => ["checkout"],
      "fix_versions" => ["1.2"],
      "links" => [{ "type" => "Blocks", "direction" => "outward", "key" => "CLD-2" }],
      "url" => "https://example.atlassian.net/browse/CLD-1",
      "created" => "2026-11-01T10:00:00.000+0000",
      "updated" => "2026-11-17T10:00:00.000+0000"
    }
  end

  def brief_data
    {
      "issue" => issue,
      "acceptance_criteria" => [],
      "decisions" => [{ "source" => "comment:c1", "author" => "Bob",
                        "text" => "We decided to use exponential backoff for the first release." }],
      "open_questions" => ["Should retries apply to all endpoints?"],
      "dependencies" => [{ "key" => "CLD-2", "type" => "Blocks", "direction" => "outward" }],
      "similar" => [],
      "recent_changes" => [{ "created" => "2026-11-17T09:00:00.000+0000", "field" => "status",
                             "from" => "To Do", "to" => "In Progress" }],
      "comments" => [{ "id" => "c1", "author" => { "display_name" => "Bob" },
                       "created" => "2026-11-16T10:00:00.000+0000", "body" => "Decision noted" }],
      "warnings" => []
    }
  end

  def git_commits
    [{
      "sha" => "abcdef123456", "author" => "Alice", "email" => "alice@example.com",
      "date" => "2026-11-15T10:00:00.000+0000", "subject" => "CLD-1 retry checkout",
      "files" => ["services/api/checkout.rb"], "files_changed" => 1, "lines_added" => 10, "lines_deleted" => 2,
      "repo" => "backend", "url" => "https://example.com/acme/backend/commit/abcdef123456"
    }]
  end

  def git_experts
    [{
      "git_identity" => { "name" => "Alice" },
      "jira_person" => { "account_id" => "u1", "display_name" => "Alice" },
      "identity_confidence" => "high", "score" => 10.0, "confidence" => "high",
      "role_hint" => ["issue_author", "recent_author"], "last_active" => "2026-11-15T10:00:00.000+0000",
      "counts" => { "commits" => 2, "files_touched" => 1, "lines_changed" => 12 },
      "repositories" => ["backend"],
      "evidence" => [{ "source" => "git_commit", "repo" => "backend", "sha" => "abcdef123456",
                       "title" => "CLD-1 retry checkout", "date" => "2026-11-15T10:00:00.000+0000",
                       "url" => "https://example.com/acme/backend/commit/abcdef123456", "kind" => "issue_commit" }]
    }]
  end

  def people
    [{
      "account_id" => "u1", "display_name" => "Alice", "confidence" => "high",
      "evidence" => [{ "source" => "jira_issue", "id" => "CLD-1", "title" => "Add retry",
                       "role" => "assignee", "url" => "https://example.atlassian.net/browse/CLD-1" }],
      "evidence_count" => 2
    }]
  end

  def context(kb_pages: [])
    JiraCore::Repositories::Context.new(
      config: config,
      issues: FakeIssues.new(brief_data),
      knowledge_base: FakeKnowledgeBase.new(kb_pages),
      people: FakePeople.new(people),
      git: FakeGit.new(git_commits, git_experts)
    )
  end

  def test_task_context_merges_sources_and_marks_contributor_as_signal
    result = context.task_context("CLD-1", sources: %w[jira kb git people])

    assert_equal "CLD-1", result["issue"]["key"]
    assert_includes result["context"]["key_people_note"], "Alice"
    assert_includes result["context"]["key_people_note"], "signal"
    assert_equal "high concentration: one author accounts for 70% of changes",
                 result["context"]["risks"].find { |risk| risk.include?("high concentration") }
    assert_equal 1, result["git"]["commits"].length
    assert(result["timeline"].any? { |item| item["source"] == "git" })
    assert(result["citations"].any? { |item| item["url"].to_s.include?("/commit/") })
    assert_includes result["context_markdown"], "## Git"
  end

  def test_clarify_issue_builds_blocking_questions_and_recipients
    result = context.clarify_issue("CLD-1", audience: "analyst", focus: %w[all], max_questions: 10)

    categories = result["questions"].map { |question| question["category"] }
    assert_includes categories, "acceptance"
    assert_includes categories, "dependencies"

    acceptance = result["questions"].find { |question| question["category"] == "acceptance" }
    assert_equal "blocking", acceptance["priority"]
    assert_equal "analyst", acceptance["owner"]

    dependency = result["questions"].find { |question| question["category"] == "dependencies" }
    assert_equal "tech_lead", dependency["owner"]
    assert_equal "R1", dependency["suggested_recipient_id"]

    assert_equal false, result["readiness"]["can_start"]
    assert_operator result["readiness"]["score"], :<, 100
    assert_includes result["message_markdown"], "## Blocking"
    assert(result["questions"].all? { |question| question["id"].to_s.start_with?("Q") })
  end

  def test_clarify_issue_marks_kb_answers_and_keeps_links
    page = {
      "id" => "p1", "title" => "Checkout retries runbook",
      "excerpt" => "Checkout retry error handling and acceptance criteria",
      "url" => "https://example.atlassian.net/wiki/spaces/CLD/pages/p1"
    }
    result = context(kb_pages: [page]).clarify_issue("CLD-1", focus: %w[acceptance])

    covered = result["questions"].select { |question| Array(question["already_answered_by"]).any? }
    refute_empty covered
    assert_includes covered.first["already_answered_by"].first["url"], "/wiki/"
  end
end
