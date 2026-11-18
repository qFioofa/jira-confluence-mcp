# frozen_string_literal: true

module JiraCld
  module Repositories
    class KnowledgeBase
      def initialize(config:, confluence:, cache:, reference: nil, logger: nil)
        @config = config
        @confluence = confluence
        @cache = cache
        @reference = reference
        @logger = logger
      end

      def enabled?
        @config.kb_enabled?
      end

      def require_enabled!
        return true if enabled?

        raise Atlassian::CapabilityError.new("Confluence knowledge base is disabled", domain: :confluence,
                                                                                      hint: "set KB_ENABLED=1 and configure spaces")
      end

      def search(query: nil, cql: nil, preset: nil, limit: 10, cursor: nil)
        require_enabled!
        raise Atlassian::QueryError.new("pass exactly one of query or cql", query_code: :query_invalid) if !query.nil? && !cql.nil?
        raise Atlassian::QueryError.new("either query or cql is required", query_code: :query_invalid) if query.nil? && cql.nil?

        order_by = Query::CQL::DEFAULT_ORDER
        clauses = []
        if preset
          preset_query, order_by, default_limit = Query::CQL.preset(@config.require_project!, preset)
          limit = default_limit if limit.nil?
          clauses << preset_query
        end
        clauses << Query::CQL.text_query(query) if query
        clauses << cql.to_s if cql

        wrapped = Query::CQL.wrap(
          Query::CQL.combine(*clauses),
          allowlist: @config.spaces,
          order_by: order_by,
          max_chars: @config.query_max_chars
        )

        logical = { cql: wrapped, limit: limit, cursor: cursor }
        fetcher = lambda do
          raw = @confluence.search(cql: wrapped, limit: limit, cursor: cursor)
          {
            "pages" => raw[:pages].map { |page| Serialize::Page.compact(page, base_url: @config.confluence_base_url, include_body: false) },
            "next_cursor" => raw[:next_cursor],
            "total" => raw[:total]
          }
        end
        data = if cursor.nil?
                 @cache.fetch(ns: "search", logical: logical, ttl: @cache.policy.ttl("search"), &fetcher)
               else
                 fetcher.call
               end
        data.merge("limit" => limit, "cql" => wrapped)
      end

      def get_page(id: nil, title: nil, space: nil)
        require_enabled!
        raise Atlassian::QueryError.new("either id or title is required", query_code: :query_invalid) if id.nil? && title.nil?
        raise Atlassian::QueryError.new("pass either id or title, not both", query_code: :query_invalid) if id && title

        page = if id
                 fetch_page(id)
               else
                 space ||= @config.space
                 raw = @confluence.page_by_title(title, space)
                 Serialize::Page.compact(raw, base_url: @config.confluence_base_url, include_body: true)
               end
        { "page" => page }
      end

      def list_children(page_id, limit: 50, cursor: nil)
        require_enabled!
        logical = { page_id: page_id.to_s, limit: limit, cursor: cursor }
        @cache.fetch(ns: "children", logical: logical, ttl: @cache.policy.ttl("children")) do
          raw = @confluence.children(page_id, limit: limit, cursor: cursor)
          {
            "page_id" => page_id.to_s,
            "children" => raw[:children],
            "next_cursor" => raw[:next_cursor],
            "total" => raw[:total]
          }
        end
      end

      def space_health
        require_enabled!
        spaces = @config.spaces.map do |space|
          info = @confluence.space(space)
          { "space" => space, "status" => "ok", "id" => info[:id], "name" => info[:name] }
        rescue Atlassian::Error => e
          { "space" => space, "status" => "error", "code" => e.code.to_s, "message" => e.message }
        end
        { "spaces" => spaces }
      end

      private

      def fetch_page(id)
        meta = @cache.fetch(ns: "page_meta", logical: { id: id.to_s },
                            ttl: @cache.policy.ttl("page_meta")) do
          raw = @confluence.page(id, include_body: false)
          { "version" => raw.dig("version", "number") || raw.dig("version", "when"),
            "title" => raw["title"] }
        end
        version = meta["version"]
        logical = { id: id.to_s, version: version }
        @cache.fetch(ns: "page", logical: logical, ttl: 3600) do
          raw = @confluence.page(id)
          Serialize::Page.compact(raw, base_url: @config.confluence_base_url, include_body: true)
        end
      end
    end
  end
end
