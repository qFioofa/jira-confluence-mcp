# frozen_string_literal: true

require "optparse"

require "json"
require "fileutils"

module JiraCld
  module CLI
    class Export
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = { output: nil }
      end

      def run
        sub = @argv.shift
        unless sub.nil? || sub == "diagnostics"
          warn("usage: jira-cld export diagnostics [--output PATH]")
          return 2
        end
        parse!
        config = Config.load(env: @env, config_path: @options[:config_path],
                             project_id: @options[:project])
        payload = diagnostics(config)
        if @options[:output]
          path = File.expand_path(@options[:output])
          FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
          File.write(path, JSON.pretty_generate(payload), perm: 0o600)
          File.chmod(0o600, path)
          $stdout.puts("diagnostics written: #{path}")
        else
          Support.print_json(payload)
        end
        0
      rescue ConfigError => e
        warn("export: #{e.message}")
        2
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--output PATH") { |value| @options[:output] = value }
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def diagnostics(config)
        {
          "generated_at" => Time.now.utc.iso8601,
          "version" => JiraCld::VERSION,
          "ruby" => RUBY_VERSION,
          "platform" => RUBY_PLATFORM,
          "config" => config.to_h(redact: true),
          "env" => redacted_env,
          "projects" => config.projects.map(&:to_h),
          "trash_bytes" => config.registry.trash_size,
          "stats_path" => config.stats_path,
          "reference_db_path" => config.reference_db_path
        }
      end

      def redacted_env
        keys = %w[JIRA_BASE_URL JIRA_DEPLOYMENT JIRA_EMAIL CONFLUENCE_BASE_URL CLD_SPACE KB_ENABLED
                  MCP_LOCALE OUTPUT_LANG MCP_PROJECT_ID CONFIG_PATH CACHE_ENABLED CACHE_SEARCH
                  LOG_LEVEL LOG_FORMAT DB_PATH STATS_PATH]
        keys.to_h { |key| [key, @env[key]] }.compact
      end
    end
  end
end
