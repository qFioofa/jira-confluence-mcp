# frozen_string_literal: true

require "json"
require "active_support/cache"

module JiraCld
  module Cache
    class DatabaseStore < ActiveSupport::Cache::Store
      Record = Struct.new(
        :key, :namespace, :value, :version, :etag, :last_modified,
        :fetched_at, :verified_at, :expires_at, :stale_until, :size,
        keyword_init: true
      ) do
        def stale?
          expires_at && Time.now.to_f * 1000 > expires_at
        end

        def hard_expired?
          stale_until && Time.now.to_f * 1000 > stale_until
        end
      end

      attr_reader :max_bytes, :stale_grace, :max_entry_bytes, :evictions

      def initialize(max_bytes:, stale_grace:, max_entry_bytes:, logger: nil, **)
        super(**)
        @max_bytes = max_bytes
        @stale_grace = stale_grace
        @max_entry_bytes = max_entry_bytes
        @logger = logger
        @evictions = 0
        @write_count = 0
        @mutex = Mutex.new
      end

      def read_record(key)
        @mutex.synchronize do
          row = fetch_row(key)
          return nil unless row

          record = row_to_record(row)
          if record.hard_expired?
            delete_key(key)
            return nil
          end
          record
        end
      rescue StandardError => e
        log_error("cache read failed", e)
        nil
      end

      def write_record(key, value, ns:, ttl: nil, version: nil, etag: nil, last_modified: nil, stale_grace: nil)
        json = JSON.generate(value)
        size = json.bytesize
        return false if size > @max_entry_bytes

        now = now_ms
        expires_at = ttl ? now + (ttl.to_i * 1000) : nil
        grace = stale_grace.nil? ? @stale_grace : stale_grace
        stale_until = expires_at && grace.to_i.positive? ? expires_at + (grace.to_i * 1000) : expires_at

        @mutex.synchronize do
          upsert!(
            ns: ns, key: key, value_json: json, version: version, etag: etag,
            last_modified: last_modified, fetched_at: now, expires_at: expires_at,
            stale_until: stale_until, size: size
          )
          @write_count += 1
          evict_if_needed! if (@write_count % 32).zero?
        end
        true
      rescue StandardError => e
        log_error("cache write failed", e)
        false
      end

      def write_multi_records(records)
        return true if records.empty?

        @mutex.synchronize do
          begin_transaction
          records.each do |record|
            json = JSON.generate(record.fetch(:value))
            next if json.bytesize > @max_entry_bytes

            ttl = record[:ttl]
            now = now_ms
            expires_at = ttl ? now + (ttl.to_i * 1000) : nil
            grace = record[:stale_grace].nil? ? @stale_grace : record[:stale_grace]
            stale_until = expires_at && grace.to_i.positive? ? expires_at + (grace.to_i * 1000) : expires_at
            upsert!(
              ns: record.fetch(:ns), key: record.fetch(:key), value_json: json,
              version: record[:version], etag: record[:etag], last_modified: record[:last_modified],
              fetched_at: now, expires_at: expires_at, stale_until: stale_until, size: json.bytesize
            )
          end
          commit_transaction
          @write_count += records.length
          evict_if_needed!
        end
        true
      rescue StandardError => e
        rollback_transaction
        log_error("cache batch write failed", e)
        false
      end

      def read_entry(key, **_options)
        record = read_record(key)
        return nil unless record

        entry = ActiveSupport::Cache::Entry.new(record.value)
        entry.expires_at = record.expires_at ? Time.at(record.expires_at / 1000.0) : nil
        entry.version = record.version
        entry
      end

      def write_entry(key, entry, **options)
        ns = options[:ns] || Key.namespace_from(key)
        ttl = options[:ttl]
        ttl ||= [(entry.expires_at - Time.now.to_f).ceil, 0].max if entry.expires_at
        write_record(
          key, entry.value, ns: ns, ttl: ttl, version: options[:version] || entry.version,
                            etag: options[:etag], last_modified: options[:last_modified], stale_grace: options[:stale_grace]
        )
      end

      def write_multi_entries(hash, **options)
        records = hash.map do |key, entry|
          ttl = options[:ttl]
          ttl ||= entry.expires_at ? [(entry.expires_at - Time.now.to_f).ceil, 0].max : nil
          {
            key: key, value: entry.value, ns: options[:ns] || Key.namespace_from(key), ttl: ttl,
            version: options[:version] || entry.version, stale_grace: options[:stale_grace],
            etag: options[:etag], last_modified: options[:last_modified]
          }
        end
        write_multi_records(records)
      end

      def delete_entry(key, **_options)
        @mutex.synchronize { delete_key(key) }
        true
      rescue StandardError
        false
      end

      def delete_multi_entries(keys, **_options)
        @mutex.synchronize do
          begin_transaction
          keys.each { |key| delete_key(key) }
          commit_transaction
        end
        true
      rescue StandardError
        rollback_transaction
        false
      end

      def delete_namespace(ns)
        @mutex.synchronize do
          run_sql("DELETE FROM cache_entries WHERE ns = ?", ns)
        end
        true
      end

      def clear(**options)
        @mutex.synchronize do
          if options[:namespace] || options[:ns]
            run_sql("DELETE FROM cache_entries WHERE ns = ?", options[:namespace] || options[:ns])
          elsif options[:expired]
            run_sql("DELETE FROM cache_entries WHERE stale_until IS NOT NULL AND stale_until < ?", now_ms)
          else
            run_sql("DELETE FROM cache_entries")
          end
        end
        true
      rescue StandardError => e
        log_error("cache clear failed", e)
        false
      end

      def cleanup(**)
        evict_if_needed!(force: true)
      end

      def stats
        counts = DB.stats
        { namespaces: counts, evictions: @evictions, bytes: DB.size_bytes, max_bytes: @max_bytes }
      rescue StandardError
        { namespaces: [], evictions: @evictions, bytes: 0, max_bytes: @max_bytes }
      end

      def evict_if_needed!(force: false)
        footprint = footprint_bytes
        return if !force && footprint <= @max_bytes

        now = now_ms
        run_sql("DELETE FROM cache_entries WHERE stale_until IS NOT NULL AND stale_until < ?", now)
        footprint = footprint_bytes
        return if footprint <= @max_bytes

        total = scalar("SELECT COUNT(*) FROM cache_entries").to_i
        batch = [(total * 0.08).ceil, 4].max
        batch = [batch, total].min
        return if batch.zero?

        run_sql(
          "DELETE FROM cache_entries WHERE rowid IN " \
          "(SELECT rowid FROM cache_entries ORDER BY fetched_at ASC LIMIT ?)", batch
        )
        @evictions += batch
      rescue StandardError => e
        log_error("cache eviction failed", e)
      end

      def checkpoint(mode = "PASSIVE")
        DB.connection.execute("PRAGMA wal_checkpoint(#{mode})")
        true
      rescue StandardError
        false
      end

      private

      def connection
        DB.connection
      end

      def now_ms
        (Time.now.to_f * 1000).to_i
      end

      def fetch_row(key)
        ns = Key.namespace_from(key)
        sql = ActiveRecord::Base.sanitize_sql_array(
          ["SELECT * FROM cache_entries WHERE ns = ? AND key = ? LIMIT 1", ns, key]
        )
        connection.exec_query(sql).first
      end

      def row_to_record(row)
        Record.new(
          key: row["key"],
          namespace: row["ns"],
          value: parse_json(row["value_json"]),
          version: row["version"],
          etag: row["etag"],
          last_modified: row["last_modified"],
          fetched_at: row["fetched_at"]&.to_i,
          verified_at: row["verified_at"]&.to_i,
          expires_at: row["expires_at"]&.to_i,
          stale_until: row["stale_until"]&.to_i,
          size: row["size"]&.to_i
        )
      end

      def parse_json(value)
        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def upsert!(ns:, key:, value_json:, version:, etag:, last_modified:, fetched_at:, expires_at:, stale_until:, size:)
        run_sql(
          "INSERT INTO cache_entries (ns, key, value_json, version, etag, last_modified, fetched_at, " \
          "expires_at, stale_until, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " \
          "ON CONFLICT(ns, key) DO UPDATE SET value_json = excluded.value_json, " \
          "version = excluded.version, etag = excluded.etag, last_modified = excluded.last_modified, " \
          "fetched_at = excluded.fetched_at, verified_at = excluded.verified_at, " \
          "expires_at = excluded.expires_at, stale_until = excluded.stale_until, size = excluded.size",
          ns, key, value_json, version, etag, last_modified, fetched_at, expires_at, stale_until, size
        )
      end

      def delete_key(key)
        run_sql("DELETE FROM cache_entries WHERE key = ?", key)
      end

      def run_sql(sql, *values)
        sanitized = ActiveRecord::Base.sanitize_sql_array([sql, *values])
        connection.exec_query(sanitized)
      end

      def scalar(sql)
        connection.select_value(sql)
      end

      def footprint_bytes
        page_count = connection.select_value("PRAGMA page_count").to_i
        freelist = connection.select_value("PRAGMA freelist_count").to_i
        page_size = connection.select_value("PRAGMA page_size").to_i
        [page_count - freelist, 0].max * page_size
      end

      def begin_transaction
        connection.execute("BEGIN IMMEDIATE")
      end

      def commit_transaction
        connection.execute("COMMIT")
      end

      def rollback_transaction
        connection.execute("ROLLBACK")
      rescue StandardError
        nil
      end

      def log_error(message, error)
        @logger&.error(message, error: error.message, class: error.class.name)
      end
    end
  end
end
