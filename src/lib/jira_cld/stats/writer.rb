# frozen_string_literal: true

require "json"

module JiraCld
  module Stats
    class Writer
      BATCH_SIZE = 64

      def initialize(config, logger: nil)
        @config = config
        @logger = logger
        @buffer = []
        @mutex = Mutex.new
      end

      def record(kind:, tool: nil, outcome: nil, cache: nil, duration_ms: nil, meta: nil, at: nil)
        return false unless @config.stats_enabled?

        event = {
          at: at || now_ms,
          project_id: @config.project_id,
          kind: kind.to_s,
          tool: tool&.to_s,
          outcome: outcome&.to_s,
          cache: cache&.to_s,
          duration_ms: duration_ms&.to_f,
          meta_json: meta && JSON.generate(meta)
        }
        flush = false
        @mutex.synchronize do
          @buffer << event
          flush = @buffer.length >= BATCH_SIZE
        end
        flush! if flush
        true
      rescue StandardError => e
        @logger&.warn("stats record failed", error: e.message)
        false
      end

      def record_tool(tool:, outcome:, duration_ms:, cache: nil, meta: nil)
        record(kind: "tool", tool: tool, outcome: outcome, cache: cache, duration_ms: duration_ms, meta: meta)
      end

      def record_cache(hit:, namespace:, source: nil)
        record(kind: "cache", outcome: hit ? "hit" : "miss", cache: source || (hit ? "hit" : "miss"),
               meta: { namespace: namespace })
      end

      def audit(action:, source:, request_id: nil, detail: nil)
        return false unless @config.stats_enabled?

        sql = ActiveRecord::Base.sanitize_sql_array(
          ["INSERT INTO audit_events (at, project_id, action, source, request_id, detail_json) " \
           "VALUES (?, ?, ?, ?, ?, ?)",
           now_ms, @config.project_id, action.to_s, source.to_s, request_id, detail && JSON.generate(detail)]
        )
        DB.stats_connection.exec_query(sql)
        true
      rescue StandardError => e
        @logger&.warn("audit write failed", error: e.message)
        false
      end

      def flush!
        rows = nil
        @mutex.synchronize do
          rows = @buffer
          @buffer = []
        end
        return true if rows.empty?

        conn = DB.stats_connection
        conn.execute("BEGIN IMMEDIATE")
        rows.each do |row|
          sql = ActiveRecord::Base.sanitize_sql_array(
            ["INSERT INTO metric_events (at, project_id, kind, tool, outcome, cache, duration_ms, meta_json) " \
             "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
             row[:at], row[:project_id], row[:kind], row[:tool], row[:outcome], row[:cache],
             row[:duration_ms], row[:meta_json]]
          )
          conn.exec_query(sql)
        end
        conn.execute("COMMIT")
        true
      rescue StandardError => e
        begin
          conn&.execute("ROLLBACK")
        rescue StandardError
          nil
        end
        @logger&.debug("stats flush skipped", error: e.message)
        false
      end

      def shutdown
        flush!
      end

      private

      def now_ms
        (Time.now.to_f * 1000).to_i
      end
    end
  end
end
