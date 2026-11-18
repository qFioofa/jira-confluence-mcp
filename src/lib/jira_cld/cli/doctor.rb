# frozen_string_literal: true

require "optparse"

require "json"
require "fileutils"

module JiraCld
  module CLI
    class Doctor
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = { offline: false, json: false, project: nil }
      end

      def run
        parse!
        checks = []
        config = Config.load(env: @env, config_path: @options[:config_path],
                             project_id: @options[:project] || @env["MCP_PROJECT_ID"])
        checks << check_config(config)
        checks << check_project(config)
        checks << check_secrets(config)
        checks << check_db(config) if config.project
        checks |= check_network(config) unless @options[:offline]
        output(config, checks)
        worst(checks)
      rescue ConfigError => e
        warn("doctor: #{e.message}") unless @options[:json]
        @options[:json] ? Support.print_json("status" => "fail", "error" => e.message) : nil
        Support::EXIT[:config]
      rescue SecretError => e
        warn("doctor: #{e.message}") unless @options[:json]
        Support::EXIT[:secret]
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--offline") { @options[:offline] = true }
          opts.on("--json") { @options[:json] = true }
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def check_config(config)
        status = config.document["schema"].to_i == ConfigStore::SCHEMA ? "ok" : "fail"
        { "name" => "config", "status" => status, "path" => config.config_path,
          "schema" => config.document["schema"] }
      end

      def check_project(config)
        if config.project_id.nil?
          return { "name" => "project", "status" => config.projects.empty? ? "fail" : "warn",
                   "message" => "MCP_PROJECT_ID is not set; mcp will fail closed", "projects" => config.projects.map(&:id) }
        end
        if config.project
          { "name" => "project", "status" => "ok", "project" => config.project_id,
            "jira_keys" => config.jira_keys, "spaces" => config.spaces }
        else
          { "name" => "project", "status" => "fail", "project" => config.project_id,
            "message" => "unknown project", "projects" => config.projects.map(&:id) }
        end
      end

      def check_secrets(config)
        refs = {
          "jira" => config.document.dig("connections", "jira", "pat_ref") ||
                    config.document.dig("connections", "jira", "token_ref") ||
                    (config.cloud? ? "env:JIRA_API_TOKEN" : "env:JIRA_PAT"),
          "confluence" => config.document.dig("connections", "confluence", "token_ref") ||
                          (config.cloud? ? "env:JIRA_API_TOKEN" : "env:CONFLUENCE_PAT")
        }
        results = refs.map do |name, ref|
          Secrets.resolve(ref, env: @env, provider: config.secret_provider)
          { "name" => name, "ref" => ref, "status" => "ok" }
        rescue SecretError => e
          { "name" => name, "ref" => ref, "status" => "fail", "message" => e.message }
        end
        status = results.all? { |item| item["status"] == "ok" } ? "ok" : "fail"
        { "name" => "secrets", "status" => status, "items" => results }
      end

      def check_db(config)
        DB.setup!(config)
        integrity = DB.integrity_check
        stat = File.stat(config.db_path)
        mode = stat.mode & 0o777
        status = integrity == "ok" && mode == 0o600 ? "ok" : "warn"
        { "name" => "db", "status" => status, "path" => config.db_path,
          "integrity" => integrity, "mode" => format("%o", mode), "bytes" => DB.size_bytes }
      rescue StandardError => e
        { "name" => "db", "status" => "fail", "message" => e.message }
      end

      def check_network(config)
        checks = []
        runtime = Runtime.build(config: config)
        begin
          user = runtime.jira.myself
          checks << { "name" => "jira", "status" => "ok", "deployment" => config.deployment,
                      "user" => Serialize::Person.compact(user, show_email: false)&.dig("display_name") }
          checks << { "name" => "jira_capabilities", "status" => "ok", "capabilities" => runtime.jira.capabilities }
          if config.jira_keys.first
            runtime.jira.project(config.jira_keys.first)
            checks << { "name" => "jira_project", "status" => "ok", "key" => config.jira_keys.first }
          end
        rescue Atlassian::Error => e
          checks << { "name" => "jira", "status" => "fail", "code" => e.code.to_s, "message" => e.message,
                      "hint" => e.hint }.compact
        rescue HTTP::Error => e
          checks << { "name" => "jira", "status" => "fail", "code" => "network", "message" => e.message }
        end

        if config.kb_enabled?
          begin
            config.spaces.each do |space|
              runtime.confluence.space(space)
              checks << { "name" => "confluence_space", "status" => "ok", "space" => space }
            end
            checks << { "name" => "confluence", "status" => "ok", "capabilities" => runtime.confluence.capabilities }
          rescue Atlassian::Error => e
            checks << { "name" => "confluence", "status" => "fail", "code" => e.code.to_s, "message" => e.message,
                        "hint" => e.hint }.compact
          rescue HTTP::Error => e
            checks << { "name" => "confluence", "status" => "fail", "code" => "network", "message" => e.message }
          end
        end
        checks
      ensure
        runtime&.close
      end

      def output(config, checks)
        if @options[:json]
          Support.print_json("status" => worst(checks).zero? ? "ok" : "fail",
                             "config" => config.to_h(redact: true), "checks" => checks)
        else
          checks.each do |check|
            status = if check["status"] == "ok"
                       "[ok]"
                     else
                       (check["status"] == "warn" ? "[warn]" : "[fail]")
                     end
            detail = check.except("name", "status").map { |key, value| "#{key}=#{value}" }.join(" ")
            $stdout.puts("#{status} #{check["name"]} #{detail}".rstrip)
          end
        end
      end

      def worst(checks)
        code = 0
        checks.each do |check|
          next if ["ok", "warn"].include?(check["status"])

          code = [code, code_for(check)].max
        end
        code
      end

      def code_for(check)
        case check["code"]
        when "auth_failed" then Support::EXIT[:auth]
        when "not_found" then Support::EXIT[:not_found]
        when "rate_limited" then Support::EXIT[:rate_limited]
        when "deployment_capability" then Support::EXIT[:capability]
        when "network" then Support::EXIT[:network]
        else
          case check["name"]
          when "secrets" then Support::EXIT[:secret]
          when "db" then Support::EXIT[:db]
          when "project", "config" then Support::EXIT[:config]
          else Support::EXIT[:network]
          end
        end
      end
    end
  end
end
