# frozen_string_literal: true

require "optparse"

require "json"

module JiraCld
  module CLI
    class CacheCommand
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = { json: false, scope: "all", yes: false }
      end

      def run
        sub = @argv.shift
        case sub
        when "stats"
          parse_stats!
          stats
        when "clear"
          parse_clear!
          clear
        when nil, "-h", "--help"
          $stdout.puts("usage: jira-cld cache <stats|clear> [--project ID] [--namespace NS] [--scope expired|all] [--yes]")
          0
        else
          warn("unknown cache command #{sub.inspect}")
          2
        end
      rescue ConfigError => e
        warn("cache: #{e.message}")
        2
      end

      private

      def parse_stats!
        parser = OptionParser.new do |opts|
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--json") { @options[:json] = true }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def parse_clear!
        parser = OptionParser.new do |opts|
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--namespace NS") { |value| @options[:namespace] = value }
          opts.on("--scope SCOPE", "expired|all") { |value| @options[:scope] = value }
          opts.on("--yes") { @options[:yes] = true }
          opts.on("--json") { @options[:json] = true }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
        raise ConfigError, "scope must be expired or all" unless %w[expired all].include?(@options[:scope])
      end

      def stats
        config = Config.load(env: @env, config_path: @options[:config_path],
                             project_id: @options[:project])
        require_project!(config)
        DB.setup!(config)
        rows = DB.stats
        payload = { "project" => config.project_id, "db_path" => config.db_path,
                    "db_size_bytes" => DB.size_bytes, "namespaces" => rows }
        if @options[:json]
          Support.print_json(payload)
        else
          $stdout.puts("Cache: #{config.db_path} (#{DB.size_bytes} bytes)")
          Support.print_table(rows.map { |row| row.transform_keys(&:to_s) },
                              %w[namespace entries bytes oldest])
        end
        0
      end

      def clear
        config = Config.load(env: @env, config_path: @options[:config_path],
                             project_id: @options[:project])
        require_project!(config)
        raise ConfigError, "refusing to clear cache without --yes" unless @options[:yes]

        DB.setup!(config)
        store = Cache::DatabaseStore.new(
          max_bytes: config.cache_max_bytes,
          stale_grace: config.cache_stale_grace,
          max_entry_bytes: config.cache_max_entry_bytes
        )
        expired = @options[:scope] == "expired"
        store.clear(namespace: @options[:namespace], expired: expired)
        DB.checkpoint("TRUNCATE")
        Stats::Writer.new(config).audit(
          action: "cache_clear", source: "cli",
          detail: { namespace: @options[:namespace], scope: @options[:scope] }
        )
        payload = { "project" => config.project_id, "scope" => @options[:scope],
                    "namespace" => @options[:namespace], "cleared" => true, "bytes" => DB.size_bytes }
        @options[:json] ? Support.print_json(payload) : $stdout.puts("cache cleared: #{payload}")
        0
      end

      def require_project!(config)
        raise ConfigError, "cache commands require --project or MCP_PROJECT_ID" unless config.project_id
        raise ConfigError, "unknown project #{config.project_id.inspect}" unless config.project
      end
    end
  end
end
