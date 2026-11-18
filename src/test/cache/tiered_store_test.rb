# frozen_string_literal: true

require_relative "../test_helper"

class TieredStoreTest < BaseTest
  def setup
    super
    write_config
    @config = config
    JiraCld::DB.setup!(@config)
    @store = build_store
  end

  def build_store
    JiraCld::Cache::TieredStore.new(
      config: @config, project: "alpha", site: "https://example.atlassian.net", principal: "dev"
    )
  end

  def test_l1_hit_avoids_block
    calls = 0
    @store.fetch(ns: "issue", logical: "a", ttl: 60) do
      calls += 1
      "value"
    end
    result = @store.fetch(ns: "issue", logical: "a", ttl: 60) do
      calls += 1
      "other"
    end
    assert_equal "value", result
    assert_equal 1, calls
    assert_equal 1, @store.stats[:hit_l1]
  end

  def test_l2_promotes_to_l1
    @store.write(ns: "issue", logical: "b", value: "persisted", ttl: 60)
    fresh = build_store
    result = fresh.fetch(ns: "issue", logical: "b", ttl: 60) { "miss" }
    assert_equal "persisted", result
    assert_equal 1, fresh.stats[:hit_l2]
  end

  def test_search_is_bypassed_by_default
    calls = 0
    2.times do
      @store.fetch(ns: "search", logical: "q", ttl: 60) do
        calls += 1
        "r"
      end
    end
    assert_equal 2, calls
    assert_equal 0, @store.stats[:hits]
  end

  def test_stale_fallback_when_revalidation_fails
    @store.write(ns: "page", logical: "stale", value: "old", ttl: 1)
    sleep 1.15
    fresh = build_store
    result = fresh.fetch_with_meta(ns: "page", logical: "stale", ttl: 1, allow_stale: true) { raise "network" }
    assert_equal "old", result.value
    assert result.stale
    assert_equal 1, fresh.stats[:stale]
  end

  def test_disabled_cache_calls_block
    config = config("CACHE_ENABLED" => "0")
    store = JiraCld::Cache::TieredStore.new(config: config, project: "alpha", site: "s")
    calls = 0
    store.fetch(ns: "issue", logical: "x") do
      calls += 1
      "v"
    end
    assert_equal 1, calls
  end
end
