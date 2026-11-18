# frozen_string_literal: true

require "optparse"

require "json"
require "fileutils"

module JiraCld
  module CLI
    class Projects
      def initialize(argv, env: ENV)
        @argv = argv.dup
        @env = env
        @options = { json: false, jira_keys: [], spaces: [], purge: false, yes: false }
      end

      def run
        sub = @argv.shift
        case sub
        when "list" then list
        when "add" then add
        when "edit" then edit
        when "remove" then remove
        when nil, "-h", "--help"
          $stdout.puts(<<~TEXT)
            usage: jira-cld projects <list|add|edit|remove> [options]
              list   [--json]
              add    --project ID [--name NAME] [--jira-key KEY]... [--space SPACE]... [--style STYLE]
              edit   --project ID [--name NAME] [--jira-key KEY]... [--space SPACE]... [--style STYLE]
              remove --project ID [--purge] --yes
          TEXT
          0
        else
          warn("unknown projects command #{sub.inspect}")
          2
        end
      rescue ConfigError => e
        warn("projects: #{e.message}")
        2
      end

      private

      def parse!
        parser = OptionParser.new do |opts|
          opts.on("--json") { @options[:json] = true }
          opts.on("--project ID") { |value| @options[:project] = value }
          opts.on("--name NAME") { |value| @options[:name] = value }
          opts.on("--jira-key KEY") { |value| @options[:jira_keys] << value }
          opts.on("--space SPACE") { |value| @options[:spaces] << value }
          opts.on("--style STYLE") { |value| @options[:style] = value }
          opts.on("--purge") { @options[:purge] = true }
          opts.on("--yes") { @options[:yes] = true }
          opts.on("--config PATH") { |value| @options[:config_path] = value }
          opts.on("-h", "--help") do
            $stdout.puts(opts)
            exit 0
          end
        end
        parser.parse!(@argv)
      end

      def list
        parse!
        config = load_config
        rows = config.projects.map(&:to_h)
        if @options[:json]
          Support.print_json("projects" => rows)
        else
          Support.print_table(rows.map { |row| row.transform_values { |v| v.is_a?(Array) ? v.join(",") : v } },
                              %w[id name key style kb_space jira_keys spaces])
        end
        0
      end

      def add
        parse!
        raise ConfigError, "--project is required" unless @options[:project]
        raise ConfigError, "--jira-key is required" unless @options[:jira_keys].any?
        raise ConfigError, "--space is required" unless @options[:spaces].any?

        config = load_config
        project = config.registry.add(
          "id" => @options[:project],
          "name" => @options[:name] || @options[:project],
          "jira_keys" => @options[:jira_keys],
          "spaces" => @options[:spaces],
          "style" => @options[:style] || "scrum",
          "related_scopes" => [],
          "queries" => Marshal.load(Marshal.dump(ConfigStore::DEFAULT_QUERIES)),
          "team" => { "show_email" => false, "channels" => [] }
        )
        create_dir(project)
        $stdout.puts("project added: #{project.id}")
        0
      end

      def edit
        parse!
        raise ConfigError, "--project is required" unless @options[:project]

        config = load_config
        project = config.registry.find!(@options[:project])
        updates = {}
        updates["name"] = @options[:name] if @options[:name]
        updates["style"] = @options[:style] if @options[:style]
        updates["jira_keys"] = (@options[:jira_keys].empty? ? project.jira_keys : (@options[:jira_keys] + project.jira_keys).uniq)
        updates["spaces"] = (@options[:spaces].empty? ? project.spaces : (@options[:spaces] + project.spaces).uniq)
        project = config.registry.update(project.id, updates)
        $stdout.puts("project updated: #{project.id}")
        0
      end

      def remove
        parse!
        raise ConfigError, "--project is required" unless @options[:project]
        raise ConfigError, "refusing to remove #{@options[:project]} without --yes (soft-delete to .trash)" unless @options[:yes]

        config = load_config
        result = config.registry.remove(@options[:project], purge: @options[:purge])
        $stdout.puts("project removed: #{result[:project_id]}")
        $stdout.puts("trashed to: #{result[:trashed_to]}") if result[:trashed_to]
        $stdout.puts("stats.db and global/reference.db were not touched")
        0
      end

      def load_config
        Config.load(env: @env, config_path: @options[:config_path], project_id: nil)
      end

      def create_dir(project)
        FileUtils.mkdir_p(project.data_dir, mode: 0o700)
        File.chmod(0o700, project.data_dir)
        File.write(project.meta_path, JSON.pretty_generate(project.to_h), perm: 0o600)
      end
    end
  end
end
