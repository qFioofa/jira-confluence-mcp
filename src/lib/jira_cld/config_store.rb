# frozen_string_literal: true

require "yaml"
require "date"
require "fileutils"
require "securerandom"

module JiraCld
  class ConfigStore
    SCHEMA = 1
    DEFAULT_QUERIES = {
      "jql" => {
        "my_work" => {
          "label" => "Моя работа",
          "query" => "assignee = currentUser() AND statusCategory != Done",
          "order_by" => "updated DESC",
          "default_limit" => 20
        },
        "sprint" => {
          "label" => "Мой спринт",
          "query" => "assignee = currentUser() AND sprint in openSprints()",
          "order_by" => "updated DESC",
          "default_limit" => 20
        },
        "review" => {
          "label" => "На ревью",
          "query" => "assignee = currentUser() AND status in (Review, \"In Review\")",
          "order_by" => "updated DESC",
          "default_limit" => 20
        },
        "blocked" => {
          "label" => "Заблокировано",
          "query" => "status = Blocked OR flagged = Impediment",
          "order_by" => "priority DESC",
          "default_limit" => 20
        },
        "recent" => {
          "label" => "Недавно обновлено",
          "query" => "assignee = currentUser() AND updated >= -7d",
          "order_by" => "updated DESC",
          "default_limit" => 20
        },
        "release_notes" => {
          "label" => "Релиз-ноты",
          "query" => "fixVersion in unreleasedVersions() AND statusCategory = Done",
          "order_by" => "updated DESC",
          "default_limit" => 50
        }
      },
      "cql" => {
        "runbooks" => {
          "label" => "Runbooks",
          "query" => "label = runbook AND type = page",
          "order_by" => "lastmodified DESC",
          "default_limit" => 10
        }
      }
    }.freeze

    attr_reader :path

    def self.default_path(env = ENV)
      env["CONFIG_PATH"] || File.expand_path("~/.config/jira-cld/config.yml")
    end

    def self.default_document
      {
        "schema" => SCHEMA,
        "connections" => {
          "jira" => { "base_url" => nil, "deployment" => "cloud", "token_ref" => "env:JIRA_API_TOKEN" },
          "confluence" => { "base_url" => nil, "token_ref" => "env:JIRA_API_TOKEN" }
        },
        "projects" => {},
        "cross_scope" => { "mode" => "confirm", "grant_ttl" => 3600, "cache" => false },
        "ui" => { "locale" => "ru", "theme" => "system" }
      }
    end

    def initialize(path: self.class.default_path)
      @path = File.expand_path(path)
    end

    def exists?
      File.file?(path)
    end

    def load
      return self.class.default_document unless exists?

      raw = YAML.safe_load_file(path, permitted_classes: [Symbol, Date, Time], aliases: true)
      validate(raw)
    rescue Psych::Exception => e
      raise ConfigError, "config.yml: #{e.message}"
    end

    def validate!(document)
      validate(document)
    end

    def save(document, backup: true)
      document = validate(deep_copy(document))
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir, mode: 0o700)
      File.chmod(0o700, dir)
      if backup && exists?
        backup_path = "#{path}.bak"
        FileUtils.cp(path, backup_path)
        File.chmod(0o600, backup_path)
      end

      tmp = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |io|
        io.write(YAML.dump(document))
        io.flush
        io.fsync
      end
      File.rename(tmp, path)
      File.chmod(0o600, path)
      document
    ensure
      FileUtils.rm_f(tmp) if defined?(tmp) && tmp
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end

    private

    def validate(document)
      raise ConfigError, "config.yml: root must be a mapping" unless document.is_a?(Hash)

      document = self.class.default_document.merge(document)
      document["schema"] ||= SCHEMA
      document["connections"] = self.class.default_document["connections"].merge(document["connections"] || {})
      document["connections"]["jira"] = self.class.default_document["connections"]["jira"]
                                            .merge(document["connections"]["jira"] || {})
      document["connections"]["confluence"] = self.class.default_document["connections"]["confluence"]
                                                  .merge(document["connections"]["confluence"] || {})
      document["projects"] = document["projects"] || {}
      document["cross_scope"] = self.class.default_document["cross_scope"].merge(document["cross_scope"] || {})
      document["ui"] = self.class.default_document["ui"].merge(document["ui"] || {})

      raise ConfigError, "config.yml: unsupported schema #{document["schema"].inspect}" unless document["schema"].to_i == SCHEMA

      raise ConfigError, "config.yml: projects must be a mapping" unless document["projects"].is_a?(Hash)

      document["projects"].each do |id, project|
        validate_project!(id, project)
      end

      mode = document.dig("cross_scope", "mode").to_s
      raise ConfigError, "config.yml: cross_scope.mode must be deny, declared or confirm" unless %w[deny declared confirm].include?(mode)

      document
    end

    def validate_project!(id, project)
      raise ConfigError, "config.yml: invalid project id #{id.inspect}" unless id.to_s.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/)
      raise ConfigError, "config.yml: project #{id} must be a mapping" unless project.is_a?(Hash)

      keys = project["jira_keys"] || []
      spaces = project["spaces"] || []
      raise ConfigError, "config.yml: project #{id}.jira_keys must be an array" unless keys.is_a?(Array)
      raise ConfigError, "config.yml: project #{id}.spaces must be an array" unless spaces.is_a?(Array)

      project["jira_keys"] = keys.map { |key| key.to_s.upcase }.reject(&:empty?)
      project["spaces"] = spaces.map(&:to_s).reject(&:empty?)
      project["style"] ||= "scrum"
      project["name"] ||= id.to_s
      project["queries"] ||= {}
      project["queries"]["jql"] ||= {}
      project["queries"]["cql"] ||= {}
      project["team"] = { "show_email" => false, "channels" => [] }.merge(project["team"] || {})
      project["related_scopes"] ||= []
      project
    end
  end
end
