# frozen_string_literal: true

require "optparse"

require "json"
require "csv"

module JiraCld
  module CLI
    class StatsCommand
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = { range: "1h", json: false, csv: false }
      end

      def run
        parse!
        config = Config.load(env: @env, config_path: @options[:config_path],
                             project_id: @options[:project])
        DB.setup!(config)
        query = Stats::Query.new(config)
        summary = query.summary(project: @options[:project], range: @options[:range])
        recent = query.recent(project: @options[:project], limit: 20)
        if @options[:json]
          Support.print_json("summary" => summary, "recent" => recent)
        elsif @options[:csv]
          $stdout.puts(CSV.generate_line(%w[at kind tool outcome cache duration_ms]))
          recent.each do |row|
            $stdout.puts(CSV.generate_line([row[:at], row[:kind], row[:tool], row[:outcome], row[:cache], row[:duration_ms]]))
          end
        else
          $stdout.puts("Range: #{summary[:range]}  project: #{@options[:project] || config.project_id || "all"}")
          $stdout.puts("Requests: #{summary[:requests]}  errors: #{summary[:errors]}  cache hit: #{summary[:hit_rate]}% " \
                       "p50: #{summary[:p50_ms]} ms  p95: #{summary[:p95_ms]} ms")
          $stdout.puts("Top tools: #{summary[:top_tools].map { |t| "#{t[:tool]}=#{t[:count]}" }.join(", ")}") unless summary[:top_tools].empty?
          $stdout.puts("Recent calls:")
          Support.print_table(recent.map { |row| row.transform_keys(&:to_s) }, %w[at tool outcome cache duration_ms])
        end
        0
      rescue Atlassian::Error => e
        warn("stats: #{e.message}")
        Support.exit_code_for(e)
      rescue ConfigError => e
        warn("stats: #{e.message}")
        2
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--range RANGE", "15m|1h|24h|7d") { |value| @options[:range] = value }
          opts.on("--json") { @options[:json] = true }
          opts.on("--csv") { @options[:csv] = true }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
        return if Stats::Query::RANGES.key?(@options[:range])

        raise ConfigError, "range must be one of #{Stats::Query::RANGES.keys.join(", ")}"
      end
    end
  end
end
