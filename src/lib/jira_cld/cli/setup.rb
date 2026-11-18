# frozen_string_literal: true

require "optparse"

require "json"

module JiraCld
  module CLI
    class Setup
      def initialize(argv, env: ENV, stdin: $stdin)
        @argv = argv.dup
        @env = env
        @stdin = stdin
        @options = {
          non_interactive: false, dry_run: false, force: false, strict_secrets: false,
          deployment: "cloud", locale: "ru", project: "alpha", name: nil,
          jira_key: nil, space: "CLD", style: "scrum"
        }
      end

      def run
        parse!
        if @options[:non_interactive]
          build!
        else
          interactive!
        end
        validate_secrets!
        document = @document
        if @options[:dry_run]
          $stdout.puts(YAML.dump(document))
          $stdout.puts("# dry-run: nothing written")
          return 0
        end
        store = ConfigStore.new(path: config_path)
        store.save(document)
        create_project_dir(document)
        $stdout.puts("config written: #{store.path}")
        $stdout.puts("project: #{@options[:project]}")
        $stdout.puts("next: make doctor PROJECT=#{@options[:project]} && make run PROJECT=#{@options[:project]}")
        0
      rescue ConfigError, SecretError => e
        warn("setup failed: #{e.message}")
        Support.exit_code_for(e)
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--non-interactive") { @options[:non_interactive] = true }
          opts.on("--dry-run") { @options[:dry_run] = true }
          opts.on("--force") { @options[:force] = true }
          opts.on("--strict-secrets") { @options[:strict_secrets] = true }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("--jira-url URL") { |value| @options[:jira_url] = value }
          opts.on("--deployment VALUE") { |value| @options[:deployment] = value }
          opts.on("--email EMAIL") { |value| @options[:email] = value }
          opts.on("--token-ref REF") { |value| @options[:token_ref] = value }
          opts.on("--pat-ref REF") { |value| @options[:pat_ref] = value }
          opts.on("--confluence-url URL") { |value| @options[:confluence_url] = value }
          opts.on("--space SPACE") { |value| @options[:space] = value }
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--name NAME") { |value| @options[:name] = value }
          opts.on("--jira-key KEY") { |value| @options[:jira_key] = value }
          opts.on("--style STYLE") { |value| @options[:style] = value }
          opts.on("--locale LANG") { |value| @options[:locale] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def interactive!
        @options[:jira_url] = ask("Jira base URL", @options[:jira_url] || @env["JIRA_BASE_URL"])
        @options[:deployment] = ask("Deployment (cloud|dc)", @options[:deployment])
        @options[:email] = ask("Jira email (Cloud)", @options[:email] || @env["JIRA_EMAIL"])
        if @options[:deployment] == "dc"
          @options[:pat_ref] = ask("Jira PAT ref", @options[:pat_ref] || "env:JIRA_PAT")
        else
          @options[:token_ref] = ask("Jira API token ref", @options[:token_ref] || "env:JIRA_API_TOKEN")
        end
        @options[:confluence_url] = ask("Confluence base URL", @options[:confluence_url] || derived_confluence_url)
        @options[:space] = ask("Confluence space", @options[:space])
        @options[:project] = ask("Project id", @options[:project])
        @options[:name] = ask("Project name", @options[:name] || @options[:project])
        @options[:jira_key] = ask("Jira project key", @options[:jira_key] || @options[:project].to_s.upcase)
        @options[:locale] = ask("Locale (ru|en)", @options[:locale])
        build!
      end

      def ask(label, default = nil)
        suffix = default.nil? || default.empty? ? "" : " [#{default}]"
        $stdout.print("#{label}#{suffix}: ")
        $stdout.flush
        answer = @stdin.gets&.strip
        answer.nil? || answer.empty? ? default : answer
      end

      def build!
        raise ConfigError, "--jira-url is required" if @options[:jira_url].nil? || @options[:jira_url].empty?
        raise ConfigError, "--project is required" if @options[:project].nil? || @options[:project].empty?

        deployment = @options[:deployment].to_s.downcase
        deployment = "dc" if %w[dc server data_center].include?(deployment)
        deployment = "cloud" unless deployment == "dc"
        jira_key = (@options[:jira_key] || @options[:project]).to_s.upcase
        token_ref = @options[:token_ref] || (deployment == "dc" ? "env:JIRA_PAT" : "env:JIRA_API_TOKEN")

        store = ConfigStore.new(path: config_path)
        document = store.exists? && !@options[:force] ? store.load : ConfigStore.default_document
        document["schema"] = ConfigStore::SCHEMA
        document["connections"]["jira"] = {
          "base_url" => @options[:jira_url].to_s.delete_suffix("/"),
          "deployment" => deployment,
          "email" => @options[:email],
          "token_ref" => token_ref
        }.compact
        document["connections"]["jira"]["pat_ref"] = @options[:pat_ref] if @options[:pat_ref]
        document["connections"]["confluence"] = {
          "base_url" => @options[:confluence_url] || derived_confluence_url,
          "token_ref" => @options[:pat_ref] ||
                         (deployment == "dc" ? "env:CONFLUENCE_PAT" : token_ref)
        }.compact

        existing = document["projects"][@options[:project].to_s] || {}
        document["projects"][@options[:project].to_s] = {
          "name" => @options[:name] || existing["name"] || @options[:project].to_s,
          "jira_keys" => (Array(existing["jira_keys"]) + [jira_key]).uniq,
          "spaces" => (Array(existing["spaces"]) + [@options[:space]]).compact.uniq,
          "style" => @options[:style] || existing["style"] || "scrum",
          "related_scopes" => existing["related_scopes"] || [],
          "queries" => existing["queries"] || Marshal.load(Marshal.dump(ConfigStore::DEFAULT_QUERIES)),
          "team" => existing["team"] || { "show_email" => false, "channels" => [] }
        }
        document["ui"] = { "locale" => @options[:locale] || "ru", "theme" => "system" }
        @document = store.validate!(document)
      end

      def validate_secrets!
        checks = []
        jira_ref = @document.dig("connections", "jira", "token_ref")
        pat_ref = @document.dig("connections", "jira", "pat_ref")
        checks << ["jira", pat_ref || jira_ref]
        checks << ["confluence", @document.dig("connections", "confluence", "token_ref")]
        checks.each do |name, ref|
          next if ref.nil? || ref.to_s.empty?

          Secrets.resolve(ref, env: @env, provider: @env["SECRET_PROVIDER"])
        rescue SecretError => e
          message = "#{name} secret #{ref}: #{e.message}"
          raise SecretError, message if @options[:strict_secrets]

          Support.warning(message)
        end
      end

      def create_project_dir(document)
        config = Config.new(env: @env, document: document, config_path: config_path,
                            project_id: @options[:project])
        project = config.project
        return unless project

        FileUtils.mkdir_p(project.data_dir, mode: 0o700)
        File.chmod(0o700, project.data_dir)
        File.write(project.meta_path, JSON.pretty_generate(project.to_h), perm: 0o600)
      end

      def derived_confluence_url
        base = @options[:jira_url] || @env["JIRA_BASE_URL"]
        return nil if base.nil? || base.empty?

        base = base.delete_suffix("/")
        base.end_with?("/wiki") ? base : "#{base}/wiki"
      end

      def config_path
        @options[:config_path] || @env["CONFIG_PATH"] || ConfigStore.default_path(@env)
      end
    end
  end
end
