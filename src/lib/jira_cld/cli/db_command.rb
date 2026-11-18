# frozen_string_literal: true

require "optparse"

module JiraCld
  module CLI
    class DBCommand
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = {}
      end

      def run
        sub = @argv.shift
        parse!
        config = Config.load(env: @env, config_path: @options[:config_path],
                             project_id: @options[:project])
        require_project!(config)
        DB.setup!(config)
        case sub
        when "migrate"
          DB.migrate!
          $stdout.puts("migrations applied: #{config.db_path}")
          0
        when "check"
          integrity = DB.integrity_check
          $stdout.puts("integrity_check: #{integrity}")
          $stdout.puts("path: #{config.db_path}")
          $stdout.puts("bytes: #{DB.size_bytes}")
          integrity == "ok" ? 0 : 5
        when "vacuum"
          before = DB.size_bytes
          DB.vacuum!
          after = DB.size_bytes
          $stdout.puts("vacuum: #{before} -> #{after} bytes")
          0
        when "checkpoint"
          DB.checkpoint("TRUNCATE")
          $stdout.puts("checkpoint: TRUNCATE")
          0
        when "stats"
          Support.print_json("db_path" => config.db_path, "namespaces" => DB.stats, "bytes" => DB.size_bytes)
          0
        else
          warn("usage: jira-cld db <migrate|check|vacuum|checkpoint|stats> [--project ID]")
          2
        end
      rescue ConfigError => e
        warn("db: #{e.message}")
        2
      rescue StandardError => e
        warn("db: #{e.message}")
        5
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def require_project!(config)
        raise ConfigError, "db commands require --project or MCP_PROJECT_ID" unless config.project_id
        raise ConfigError, "unknown project #{config.project_id.inspect}" unless config.project
      end
    end
  end
end
