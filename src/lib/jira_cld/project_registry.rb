# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module JiraCld
  class ProjectRegistry
    class Project
      attr_reader :id, :config, :base_dir

      def initialize(id:, config:, base_dir:)
        @id = id.to_s
        @config = config || {}
        @base_dir = base_dir
      end

      def name
        config["name"] || id
      end

      def jira_keys
        Array(config["jira_keys"]).map { |key| key.to_s.upcase }
      end

      def spaces
        Array(config["spaces"]).map(&:to_s)
      end

      def style
        config["style"] || "scrum"
      end

      def aliases
        Array(config["aliases"]).map(&:to_s)
      end

      def related_scopes
        Array(config["related_scopes"])
      end

      def team
        config["team"] || {}
      end

      def queries
        config["queries"] || {}
      end

      def jql_presets
        queries["jql"] || {}
      end

      def cql_presets
        queries["cql"] || {}
      end

      def jql_preset(id)
        jql_presets[id.to_s]
      end

      def cql_preset(id)
        cql_presets[id.to_s]
      end

      def cross_scope
        config["cross_scope"] || {}
      end

      def capabilities
        {
          "jira" => { "search" => true, "issues" => true, "agile" => true, "comments" => true, "attachments" => true },
          "confluence" => { "search" => true, "pages" => true, "children" => true, "body_view" => true }
        }
      end

      def data_dir
        File.join(base_dir, id)
      end

      def cache_db_path
        File.join(data_dir, "cache.db")
      end

      def meta_path
        File.join(data_dir, "meta.json")
      end

      def to_h
        {
          id: id,
          key: jira_keys.first,
          name: name,
          style: style,
          capabilities: capabilities,
          kb_space: spaces.first,
          spaces: spaces,
          jira_keys: jira_keys,
          aliases: aliases
        }
      end

      def describe(include_query: false)
        to_h.merge(
          query_presets: preset_descriptions(include_query: include_query),
          members: [],
          roles: [],
          component_leads: [],
          tools: [],
          boards: []
        )
      end

      def preset_descriptions(include_query: false)
        list = []
        jql_presets.each do |id, preset|
          item = { id: id, kind: "jql", label: preset["label"] || id,
                   description: preset["description"], default_limit: preset["default_limit"] || 20 }
          item[:query] = preset["query"] if include_query
          list << item.compact
        end
        cql_presets.each do |id, preset|
          item = { id: id, kind: "cql", label: preset["label"] || id,
                   description: preset["description"], default_limit: preset["default_limit"] || 10 }
          item[:query] = preset["query"] if include_query
          list << item.compact
        end
        list
      end
    end

    attr_reader :base_dir

    def initialize(document, base_dir:, config_store: nil, env: ENV)
      @document = document
      @base_dir = File.expand_path(base_dir)
      @config_store = config_store || ConfigStore.new
      @env = env
    end

    def list
      @document.fetch("projects", {}).map do |id, cfg|
        Project.new(id: id, config: cfg, base_dir: base_dir)
      end.sort_by(&:id)
    end

    def find(id)
      return nil if id.nil?

      cfg = @document.fetch("projects", {})[id.to_s]
      cfg ? Project.new(id: id.to_s, config: cfg, base_dir: base_dir) : nil
    end

    def find!(id)
      find(id) || raise(ConfigError, "unknown project #{id.inspect}")
    end

    def resolve(query)
      q = query.to_s.downcase.strip
      return { candidates: [], needs_confirmation: false } if q.empty?

      candidates = list.select do |project|
        haystack = [project.id, project.name, project.jira_keys, project.spaces, project.aliases].flatten.join(" ").downcase
        haystack.include?(q)
      end
      { candidates: candidates.map(&:to_h), needs_confirmation: candidates.length != 1 }
    end

    def add(project_document)
      id = project_document.fetch("id")
      doc = @config_store.load
      doc["projects"] ||= {}
      doc["projects"][id.to_s] = project_document.reject { |k, _| k.to_s == "id" }
      @config_store.save(doc)
      @document = doc
      find(id)
    end

    def update(id, updates)
      doc = @config_store.load
      current = doc.dig("projects", id.to_s)
      raise ConfigError, "unknown project #{id.inspect}" unless current

      doc["projects"][id.to_s] = current.merge(updates.reject { |k, _| k.to_s == "id" })
      @config_store.save(doc)
      @document = doc
      find(id)
    end

    def remove(id, purge: false)
      doc = @config_store.load
      project = doc.dig("projects", id.to_s)
      raise ConfigError, "unknown project #{id.inspect}" unless project

      project_obj = find(id)
      doc["projects"].delete(id.to_s)
      @config_store.save(doc)
      @document = doc

      trash = nil
      if project_obj && Dir.exist?(project_obj.data_dir)
        trash = File.join(base_dir, ".trash", "#{id}-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}")
        FileUtils.mkdir_p(File.dirname(trash), mode: 0o700)
        FileUtils.mv(project_obj.data_dir, trash)
        File.chmod(0o700, trash)
      end

      Dir.glob(File.join(base_dir, ".trash", "#{id}-*")).each { |path| FileUtils.rm_rf(path) } if purge

      { project_id: id, trashed_to: trash, purged: purge }
    end

    def trash_size
      Dir.glob(File.join(base_dir, ".trash", "*")).sum do |path|
        if File.file?(path)
          File.size(path)
        else
          Dir.glob(File.join(path, "**", "*")).sum { |f| File.file?(f) ? File.size(f) : 0 }
        end
      rescue SystemCallError
        0
      end
    end
  end
end
