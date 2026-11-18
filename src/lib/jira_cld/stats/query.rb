# frozen_string_literal: true

require "json"

module JiraCld
  module Stats
    class Query
      RANGES = {
        "15m" => 15 * 60,
        "1h" => 60 * 60,
        "24h" => 24 * 60 * 60,
        "7d" => 7 * 24 * 60 * 60
      }.freeze

      def initialize(config = nil)
        @config = config
      end

      def range_seconds(range)
        RANGES.fetch(range.to_s, RANGES["1h"])
      end

      def summary(project: nil, range: "1h")
        since = now_ms - (range_seconds(range) * 1000)
        where = ["at >= ?"]
        values = [since]
        if project
          where << "project_id = ?"
          values << project
        end
        clause = where.join(" AND ")
        events = DB.stats_connection.exec_query(
          ActiveRecord::Base.sanitize_sql_array(
            ["SELECT kind, outcome, cache, duration_ms, tool FROM metric_events WHERE #{clause}", *values]
          )
        ).to_a
        durations = events.filter_map { |e| e["duration_ms"]&.to_f }.sort
        tools = events.select { |e| e["kind"] == "tool" }
        hits = events.count { |e| e["kind"] == "cache" && e["outcome"] == "hit" }
        misses = events.count { |e| e["kind"] == "cache" && e["outcome"] == "miss" }
        errors = tools.count { |e| %w[error failure].include?(e["outcome"].to_s) }
        {
          range: range,
          requests: tools.length,
          errors: errors,
          cache_hits: hits,
          cache_misses: misses,
          hit_rate: ratio(hits, hits + misses),
          p50_ms: percentile(durations, 0.50),
          p95_ms: percentile(durations, 0.95),
          top_tools: top_tools(tools)
        }
      end

      def recent(project: nil, limit: 20)
        where = []
        values = []
        if project
          where << "project_id = ?"
          values << project
        end
        clause = where.empty? ? "" : "WHERE #{where.join(" AND ")}"
        rows = DB.stats_connection.exec_query(
          ActiveRecord::Base.sanitize_sql_array(
            ["SELECT at, tool, outcome, cache, duration_ms, kind FROM metric_events #{clause} " \
             "ORDER BY at DESC LIMIT ?", *values, limit.to_i]
          )
        ).to_a
        rows.map do |row|
          {
            at: iso(row["at"]),
            kind: row["kind"],
            tool: row["tool"],
            outcome: row["outcome"],
            cache: row["cache"],
            duration_ms: row["duration_ms"]&.to_f
          }
        end
      end

      def timeseries(project: nil, range: "1h", buckets: 60)
        since = now_ms - (range_seconds(range) * 1000)
        values = [since]
        where = "at >= ?"
        if project
          where += " AND project_id = ?"
          values << project
        end
        rows = DB.stats_connection.exec_query(
          ActiveRecord::Base.sanitize_sql_array(
            ["SELECT at, kind, outcome FROM metric_events WHERE #{where} ORDER BY at ASC", *values]
          )
        ).to_a
        bucket_ms = [(range_seconds(range) * 1000) / buckets.to_i, 1].max
        series = Array.new(buckets.to_i) { { requests: 0, cache_hits: 0, errors: 0 } }
        rows.each do |row|
          index = [((row["at"].to_i - since) / bucket_ms), buckets.to_i - 1].min
          next if index.negative?

          if row["kind"] == "tool"
            series[index][:requests] += 1
            series[index][:errors] += 1 if %w[error failure].include?(row["outcome"].to_s)
          elsif row["kind"] == "cache" && row["outcome"] == "hit"
            series[index][:cache_hits] += 1
          end
        end
        series.each_with_index.map do |item, index|
          { at: iso(since + (index * bucket_ms)) }.merge(item)
        end
      end

      def cache_namespaces(project: nil)
        DB.stats
      rescue StandardError
        []
      end

      private

      def top_tools(tools)
        grouped = tools.group_by { |e| e["tool"] }.filter_map do |name, list|
          next if name.nil?

          { tool: name, count: list.length }
        end
        grouped.sort_by { |e| -e[:count] }.first(5)
      end

      def percentile(sorted, p)
        return 0 if sorted.empty?

        index = [(sorted.length - 1) * p, 0].max
        low = sorted[index.floor]
        high = sorted[index.ceil] || low
        ((low + ((high - low) * (index - index.floor))) * 100).round / 100.0
      end

      def ratio(a, b)
        return 0 if b.zero?

        ((a.to_f / b) * 100).round(1)
      end

      def now_ms
        (Time.now.to_f * 1000).to_i
      end

      def iso(ms)
        Time.at(ms.to_i / 1000.0).utc.iso8601
      end
    end
  end
end
