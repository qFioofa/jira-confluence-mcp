# frozen_string_literal: true

require "test_helper"

class JiraCacheStoreTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @team = create_team(user: @user)
    @jira = create_connection(team: @team)
    @project = create_project(team: @team, jira: @jira)
    @cache = ActiveSupport::Cache::MemoryStore.new
    @resolver = JiraCache::StrategyResolver.new(project: @project, user: @user, connections: [@jira])
  end

  test "misses once and hits on the second read" do
    store = build_store(@user)
    calls = 0

    first = store.fetch(ns: "issue", logical: { key: "CLD-1" }) { calls += 1; { "key" => "CLD-1" } }
    second = store.fetch(ns: "issue", logical: { key: "CLD-1" }) { calls += 1; { "key" => "CLD-1" } }

    assert_equal first, second
    assert_equal 1, calls
    assert_equal 1, store.stats[:misses]
    assert_equal 1, store.stats[:hits]
  end

  test "cache keys are isolated by user" do
    other = create_user(email: "other@example.com")
    first = build_store(@user)
    second = build_store(other)

    first.fetch(ns: "issue", logical: { key: "CLD-1" }) { "user-one" }

    calls = 0
    value = second.fetch(ns: "issue", logical: { key: "CLD-1" }) { calls += 1; "user-two" }

    assert_equal "user-two", value
    assert_equal 1, calls
  end

  test "flushes aggregated cache events" do
    store = build_store(@user)
    store.fetch(ns: "issue", logical: { key: "CLD-1" }) { "one" }
    store.fetch(ns: "issue", logical: { key: "CLD-1" }) { "one" }
    store.flush_stats!

    events = CacheEvent.where(project: @project, namespace: "issue")
    assert_equal 2, events.sum(:count)
    assert_equal 1, events.where(source: "miss").count
    assert_equal 1, events.where(source: "hit").count
  end

  test "clear invalidates all project keys" do
    store = build_store(@user)
    store.fetch(ns: "issue", logical: { key: "CLD-1" }) { "old" }

    assert store.clear

    calls = 0
    value = store.fetch(ns: "issue", logical: { key: "CLD-1" }) { calls += 1; "new" }

    assert_equal "new", value
    assert_equal 1, calls
  end

  test "a new project gets default strategies" do
    namespaces = CacheStrategy.where(project: @project).pluck(:namespace)

    assert_includes namespaces, "issue"
    assert_includes namespaces, "page"
    assert_includes namespaces, "search"
  end

  test "project strategy overrides the default ttl" do
    strategy = CacheStrategy.find_by!(
      project: @project,
      user_id: nil,
      connection_id: nil,
      namespace: "issue"
    )
    strategy.update!(ttl_seconds: 5, stale_grace_seconds: 0)

    resolver = JiraCache::StrategyResolver.new(project: @project, user: @user, connections: [@jira])

    assert_equal 5, resolver.ttl("issue")
    refute resolver.stale?("issue")
  end

  private

  def build_store(user)
    JiraCache::RailsStore.new(
      cache: @cache,
      user: user,
      project: @project,
      connections: [@jira],
      resolver: JiraCache::StrategyResolver.new(project: @project, user: user, connections: [@jira]),
      logger: StructuredLogger.new(Rails.logger)
    )
  end
end
