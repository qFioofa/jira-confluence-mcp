# frozen_string_literal: true

module JiraCore
  class ProjectRegistry
    class Project
      attr_reader :id, :config

      def initialize(id:, config:)
        @id = id.to_s
        @config = config || {}
      end

      def name
        config["name"] || config[:name] || id
      end

      def jira_keys
        Array(config["jira_keys"] || config[:jira_keys]).map { |key| key.to_s.upcase }
      end

      def spaces
        Array(config["spaces"] || config[:spaces]).map(&:to_s)
      end

      def style
        config["style"] || config[:style] || "scrum"
      end

      def aliases
        Array(config["aliases"] || config[:aliases]).map(&:to_s)
      end

      def related_scopes
        Array(config["related_scopes"] || config[:related_scopes])
      end

      def team
        config["team"] || config[:team] || {}
      end

      def queries
        config["queries"] || config[:queries] || {}
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
        config["cross_scope"] || config[:cross_scope] || {}
      end

      def capabilities
        {
          "jira" => { "search" => true, "issues" => true, "agile" => true, "comments" => true, "attachments" => true },
          "confluence" => { "search" => true, "pages" => true, "children" => true, "body_view" => true }
        }
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
        presets = preset_descriptions(include_query: include_query)
        to_h.merge(
          query_presets: presets,
          warnings: describe_warnings,
          members: [],
          roles: [],
          component_leads: [],
          tools: [],
          boards: []
        )
      end

      def describe_warnings
        warnings = []
        if jql_presets.empty?
          warnings << "no JQL presets configured for this project; jira_my_work and jira_search_issues use built-in queries (assigned/recent work out of the box)"
        end
        if cql_presets.empty?
          warnings << "no CQL presets configured; knowledge base search runs without a preset"
        end
        warnings
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

    def initialize(projects)
      @projects = Array(projects).map do |item|
        Project.new(id: item["id"] || item[:id], config: item["config"] || item)
      end
    end

    def list
      @projects
    end

    def find(id)
      return nil if id.nil?

      @projects.find { |project| project.id == id.to_s }
    end

    def find!(id)
      find(id) || raise(ConfigError, "unknown project #{id.inspect}")
    end

    def resolve(query)
      q = query.to_s.downcase.strip
      return { candidates: [], needs_confirmation: false } if q.empty?

      candidates = @projects.select do |project|
        haystack = [project.id, project.name, project.jira_keys, project.spaces, project.aliases].flatten.join(" ").downcase
        haystack.include?(q)
      end
      { candidates: candidates.map(&:to_h), needs_confirmation: candidates.length != 1 }
    end
  end
end
