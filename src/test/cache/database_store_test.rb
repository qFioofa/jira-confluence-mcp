# frozen_string_literal: true

require_relative "../test_helper"

class DatabaseStoreTest < BaseTest
  def setup
    super
    write_config
    @config = config
    JiraCld::DB.setup!(@config)
    @store = JiraCld::Cache::DatabaseStore.new(
      max_bytes: @config.cache_max_bytes,
      stale_grace: 60,
      max_entry_bytes: @config.cache_max_entry_bytes
    )
    @key = JiraCld::Cache::Key.build(project: "alpha", site: "https://example.atlassian.net",
                                     principal: "dev", ns: "issue", logical: { key: "CLD-1" })
  end

  def test_write_and_read_round_trip
    assert @store.write_record(@key, { "key" => "CLD-1", "summary" => "Hello" }, ns: "issue", ttl: 60)
    record = @store.read_record(@key)
    assert_equal "CLD-1", record.value["key"]
    assert_equal "Hello", record.value["summary"]
    refute record.stale?
  end

  def test_read_does_not_update_accessed_at_or_fetched_at
    @store.write_record(@key, { "v" => 1 }, ns: "issue", ttl: 60)
    first = @store.read_record(@key)
    sleep 0.01
    second = @store.read_record(@key)
    assert_equal first.fetched_at, second.fetched_at
    value = JiraCld::DB.connection.select_value(
      "SELECT accessed_at FROM cache_entries WHERE key = #{JiraCld::DB.connection.quote(@key)}"
    )
    assert_nil value
  end

  def test_hard_expiry_removes_entry
    @store.write_record(@key, { "v" => 1 }, ns: "issue", ttl: 1, stale_grace: 0)
    sleep 1.15
    assert_nil @store.read_record(@key)
    count = JiraCld::DB.connection.select_value("SELECT COUNT(*) FROM cache_entries")
    assert_equal 0, count
  end

  def test_stale_record_is_returned_with_flag
    @store.write_record(@key, { "v" => 1 }, ns: "issue", ttl: 1, stale_grace: 60)
    sleep 1.15
    record = @store.read_record(@key)
    refute_nil record
    assert record.stale?
    refute record.hard_expired?
  end

  def test_entry_larger_than_limit_is_rejected
    store = JiraCld::Cache::DatabaseStore.new(max_bytes: 1024, stale_grace: 0, max_entry_bytes: 8)
    refute store.write_record(@key, { "value" => "x" * 100 }, ns: "issue", ttl: 60)
  end

  def test_batch_upsert
    records = (1..10).map do |index|
      {
        key: JiraCld::Cache::Key.build(project: "alpha", site: "s", principal: "p", ns: "search",
                                       logical: { i: index }),
        ns: "search", value: { "i" => index }, ttl: 60
      }
    end
    assert @store.write_multi_records(records)
    assert_equal 10, JiraCld::DB.connection.select_value("SELECT COUNT(*) FROM cache_entries")
    records.each do |record|
      assert_equal record[:value], @store.read_record(record[:key]).value
    end
  end

  def test_clear_by_namespace_and_expired
    @store.write_record(@key, { "v" => 1 }, ns: "issue", ttl: 60)
    other = JiraCld::Cache::Key.build(project: "alpha", site: "s", principal: "p", ns: "page", logical: 1)
    @store.write_record(other, { "v" => 2 }, ns: "page", ttl: 60)
    @store.clear(namespace: "issue")
    assert_nil @store.read_record(@key)
    refute_nil @store.read_record(other)
    @store.clear
    assert_nil @store.read_record(other)
  end

  def test_pragmas
    assert_equal "wal", JiraCld::DB.connection.select_value("PRAGMA journal_mode").downcase
    assert_equal 1, JiraCld::DB.connection.select_value("PRAGMA synchronous").to_i
    assert_equal 2, JiraCld::DB.connection.select_value("PRAGMA temp_store").to_i
    assert_equal 8192, JiraCld::DB.connection.select_value("PRAGMA page_size").to_i
    assert_equal(-8192, JiraCld::DB.connection.select_value("PRAGMA cache_size").to_i)
  end
end
