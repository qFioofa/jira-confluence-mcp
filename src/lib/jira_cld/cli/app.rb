# frozen_string_literal: true

require "optparse"

module JiraCld
  module CLI
    class App
      COMMANDS = %w[mcp mcp-http ui setup doctor projects stats cache db config export console version].freeze

      def initialize(argv, env: ENV, stdin: $stdin, stdout: $stdout, stderr: $stderr)
        @argv = argv.dup
        @env = env
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
      end

      def run
        command = @argv.shift
        case command
        when "mcp" then run_mcp
        when "mcp-http" then run_mcp(http: true)
        when "ui" then run_ui
        when "setup" then Setup.new(@argv, env: @env, stdin: @stdin).run
        when "doctor" then Doctor.new(@argv, env: @env).run
        when "projects" then Projects.new(@argv, env: @env).run
        when "stats" then StatsCommand.new(@argv, env: @env).run
        when "cache" then CacheCommand.new(@argv, env: @env).run
        when "db" then DBCommand.new(@argv, env: @env).run
        when "config" then ConfigCommand.new(@argv, env: @env).run
        when "export" then Export.new(@argv, env: @env).run
        when "console" then run_console
        when "version", "--version", "-v"
          @stdout.puts(JiraCld::VERSION)
          0
        when nil, "-h", "--help", "help"
          help
          0
        else
          @stderr.puts("unknown command #{command.inspect}")
          help
          2
        end
      rescue Interrupt
        130
      rescue StandardError => e
        @stderr.puts("error: #{e.message}")
        @env["JIRA_CLD_DEBUG"] ? @stderr.puts(e.backtrace) : nil
        Support.exit_code_for(e)
      end

      private

      def run_mcp(http: false)
        options = parse_mcp_options!
        config = Config.load(env: @env)
        config.require_project!
        logger = Logging.build(config)
        runtime = Runtime.build(config: config, logger: logger)
        JiraCld.runtime = runtime
        server = Server.build(config: config, logger: logger, runtime: runtime)
        if http || options[:http]
          server.run_http(
            host: options[:host] || config.mcp_http_host,
            port: options[:port] || config.mcp_http_port,
            path: options[:path] || config.mcp_http_path,
            stateless: options[:stateless].nil? ? config.mcp_http_stateless? : options[:stateless],
            allowed_hosts: config.mcp_http_allowed_hosts
          )
        else
          server.run
        end
        0
      end

      def parse_mcp_options!
        options = {}
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: jira-cld mcp [--http] [--host HOST] [--port PORT] [--path PATH] [--stateless|--stateful]"
          opts.on("--http") { options[:http] = true }
          opts.on("--host HOST") { |value| options[:host] = value }
          opts.on("--port PORT", Integer) { |value| options[:port] = value }
          opts.on("--path PATH") { |value| options[:path] = value }
          opts.on("--stateless") { options[:stateless] = true }
          opts.on("--stateful") { options[:stateless] = false }
          opts.on("-h", "--help") do
            @stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
        options
      rescue OptionParser::ParseError => e
        @stderr.puts("error: #{e.message}")
        exit 2
      end

      def run_ui
        config = Config.load(env: @env)
        require "jira_cld/ui/app"
        JiraCld::UI::App.run(config: config, env: @env)
        0
      rescue LoadError => e
        @stderr.puts("UI gems are not installed (#{e.message}). Install the :ui group: bundle config unset --local without && bundle install")
        2
      end

      def run_console
        config = Config.load(env: @env)
        logger = Logging.build(config)
        runtime = Runtime.build(config: config, logger: logger)
        JiraCld.runtime = runtime
        require "irb"
        IRB.start
        0
      ensure
        runtime&.close
      end

      def help
        @stdout.puts(<<~TEXT)
          ruby-jira-mcp #{JiraCld::VERSION}

          Usage: jira-cld <command> [options]

          Commands:
            mcp        run the MCP server (stdio by default, --http for Streamable HTTP)
            mcp-http   run the Streamable HTTP MCP server on 127.0.0.1:8765/mcp
            ui         run the local read-only UI (optional :ui group)
            setup      create or update config.yml (interactive or --non-interactive)
            doctor     validate config, secrets, DB and optional network access
            projects   list|add|edit|remove projects (soft-delete to .trash)
            stats      show statistics (--json, --csv, --range)
            cache      cache stats|clear
            db         db migrate|check|vacuum|checkpoint
            config     config show|validate|path|print-opencode
            export     export diagnostics
            console    irb with boot
            version    print version
        TEXT
      end
    end
  end
end
