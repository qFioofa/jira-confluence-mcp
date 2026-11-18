# frozen_string_literal: true

require "optparse"

require "json"

module JiraCld
  module CLI
    class ConfigCommand
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = { json: false }
      end

      def run
        sub = @argv.shift
        parse!
        case sub
        when "show"
          show
        when "validate"
          validate
        when "path"
          config = load_config
          $stdout.puts(config.config_path)
          0
        when "print-opencode"
          print_opencode
        when nil, "-h", "--help"
          $stdout.puts("usage: jira-cld config <show|validate|path|print-opencode> [--config PATH] [--json] [--http] [--host HOST] [--port PORT] [--path PATH]")
          0
        else
          warn("unknown config command #{sub.inspect}")
          2
        end
      rescue ConfigError => e
        warn("config: #{e.message}")
        2
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--json") { @options[:json] = true }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--http") { @options[:http] = true }
          opts.on("--host HOST") { |value| @options[:host] = value }
          opts.on("--port PORT", Integer) { |value| @options[:port] = value }
          opts.on("--path PATH") { |value| @options[:path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def load_config
        Config.load(env: @env, config_path: @options[:config_path], project_id: @options[:project])
      end

      def show
        config = load_config
        payload = config.to_h(redact: true)
        @options[:json] ? Support.print_json(payload) : payload.each { |key, value| $stdout.puts("#{key}: #{value}") }
        0
      end

      def validate
        store = ConfigStore.new(path: @options[:config_path] || @env["CONFIG_PATH"] || ConfigStore.default_path(@env))
        document = store.load
        store.validate!(document)
        $stdout.puts("config ok: #{store.path}")
        0
      end

      def print_opencode
        config = load_config
        project = @options[:project] || @env["MCP_PROJECT_ID"] || config.projects.first&.id
        entry = if @options[:http]
                  { "type" => "remote", "url" => http_url(config), "enabled" => true }
                else
                  {
                    "type" => "local",
                    "command" => ["bundle", "exec", "bin/jira-cld", "mcp"],
                    "cwd" => Dir.pwd,
                    "pool" => false,
                    "environment" => {
                      "MCP_PROJECT_ID" => project || "alpha",
                      "JIRA_API_TOKEN" => "{env:JIRA_API_TOKEN}"
                    }
                  }
                end
        snippet = { "mcp" => { "servers" => { "jira-#{project || "alpha"}" => entry } } }
        $stdout.puts(JSON.pretty_generate(snippet))
        0
      end

      def http_url(config)
        host = @options[:host] || config.mcp_http_host
        host = "127.0.0.1" if host == "0.0.0.0"
        port = @options[:port] || config.mcp_http_port
        path = @options[:path] || config.mcp_http_path
        path = "/#{path}" unless path.start_with?("/")
        path = path.chomp("/") while path.length > 1 && path.end_with?("/")
        "http://#{host}:#{port}#{path}"
      end
    end
  end
end
