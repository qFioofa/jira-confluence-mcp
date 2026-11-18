# frozen_string_literal: true

require "json"

module JiraCld
  module Repositories
    class Reference
      TTL = 24 * 60 * 60

      def initialize(config:, logger: nil)
        @config = config
        @logger = logger
      end

      def get(ns, key)
        conn = DB.reference_connection
        sql = ActiveRecord::Base.sanitize_sql_array(
          ["SELECT value_json, expires_at FROM reference_entries WHERE ns = ? AND key = ? LIMIT 1", ns.to_s, key.to_s]
        )
        row = conn.exec_query(sql).first
        return nil unless row
        return nil if row["expires_at"] && row["expires_at"].to_i < now_ms

        JSON.parse(row["value_json"])
      rescue StandardError => e
        @logger&.warn("reference read failed", error: e.message)
        nil
      end

      def put(ns, key, value, ttl: TTL, version: nil)
        conn = DB.reference_connection
        expires = now_ms + (ttl.to_i * 1000)
        sql = ActiveRecord::Base.sanitize_sql_array(
          ["INSERT INTO reference_entries (ns, key, value_json, version, expires_at, fetched_at) " \
           "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(ns, key) DO UPDATE SET value_json = excluded.value_json, " \
           "version = excluded.version, expires_at = excluded.expires_at, fetched_at = excluded.fetched_at",
           ns.to_s, key.to_s, JSON.generate(value), version, expires, now_ms]
        )
        conn.exec_query(sql)
        value
      rescue StandardError => e
        @logger&.warn("reference write failed", error: e.message)
        value
      end

      def fetch(ns, key, ttl: TTL)
        cached = get(ns, key)
        return cached unless cached.nil?

        value = yield
        put(ns, key, value, ttl: ttl)
        value
      end

      def clear
        DB.reference_connection.execute("DELETE FROM reference_entries")
      end

      private

      def now_ms
        (Time.now.to_f * 1000).to_i
      end
    end
  end
end
