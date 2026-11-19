# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "open3"
require "fileutils"

class GitRepositoryTest < CoreTest
  def setup
    super
    @dir = Dir.mktmpdir("jira-mcp-git")
    git("init", "-q")
    FileUtils.mkdir_p(File.join(@dir, "services", "api"))
    write("services/api/handler.rb", "def handle\n  retry_request\nend\n")
    commit("CLD-1 add api handler", author: "Alice", email: "alice@example.com")
    write("services/api/handler.rb", "def handle\n  retry_request(backoff: true)\nend\n")
    commit("refactor retry", author: "Bob", email: "bob@example.com")
    write("services/api/handler.rb", "def handle\n  retry_request(backoff: true, limit: 3)\nend\n")
    commit("CLD-1 follow-up", author: "Alice", email: "alice@example.com")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_experts_rank_issue_authors_first
    repo = build_git
    result = repo.experts(issue_key: "CLD-1", component: "API", since: "30d", limit: 5)

    names = result["experts"].map { |expert| expert.dig("git_identity", "name") }
    assert_equal "Alice", names.first
    assert_includes names, "Bob"
    assert_includes result["experts"].first["role_hint"], "issue_author"
    assert_equal 2, result["experts"].first["counts"]["commits"]
    assert_equal "backend", result["repositories"].first
  end

  def test_find_issue_refs_returns_commits_and_urls
    repo = build_git
    result = repo.find_issue_refs("CLD-1", since: "30d")

    assert_equal 2, result["commits"].length
    assert(result["commits"].all? { |commit| commit["repo"] == "backend" })
    assert(result["commits"].all? { |commit| commit["url"].include?("/commit/") })
  end

  def test_file_history_and_search_code
    repo = build_git
    history = repo.file_history("backend", "services/api", since: "30d")
    assert_equal 3, history["total"]

    matches = repo.search_code("backend", "retry_request")
    assert_equal 1, matches["matches"].length
    assert_includes matches["matches"].first["path"], "services/api/handler.rb"
    assert_includes matches["matches"].first["url"], "/blob/main/"
  end

  def test_identity_map_resolves_jira_person
    repo = build_git(git_author_map: { "alice@example.com" => { "account_id" => "acc-1", "display_name" => "Alice A" } })
    result = repo.experts(issue_key: "CLD-1", since: "30d", limit: 1)
    person = result["experts"].first["jira_person"]

    assert_equal "acc-1", person["account_id"]
    assert_equal "Alice A", person["display_name"]
    assert_equal "high", result["experts"].first["identity_confidence"]
  end

  def test_unknown_repo_is_rejected
    repo = build_git
    assert_raises(ArgumentError) { repo.file_history("nope", "services/api") }
  end

  private

  def build_git(git_author_map: {})
    cfg = config(
      git_repos: [{
        "id" => "backend",
        "path" => @dir,
        "url" => "https://example.com/acme/backend",
        "provider" => "github",
        "jira_keys" => ["CLD"],
        "components" => { "API" => "services/api" }
      }],
      git_author_map: git_author_map
    )
    JiraCore::Repositories::Git.new(config: cfg, cache: JiraCore::Cache::MemoryStore.new)
  end

  def write(relative, content)
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def commit(message, author:, email:)
    git("add", ".")
    git("-c", "user.name=#{author}", "-c", "user.email=#{email}", "commit", "-q", "-m", message)
  end

  def git(*args)
    stdout, stderr, status = Open3.capture3("git", "-C", @dir, *args)
    raise "git #{args.join(" ")} failed: #{stderr}#{stdout}" unless status.success?

    stdout
  end
end
