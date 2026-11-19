# frozen_string_literal: true

module JiraCore
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
            "pages" => raw[:pages].map { |page| Serialize::Page.compact(page, base_url: @config.confluence_web_base_url, include_body: false) },
            "next_cursor" => raw[:next_cursor],
            "total" => raw[:total]
          }
        end
        data = if cursor.nil?
                 @cache.fetch(ns: "search", logical: logical, &fetcher)
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
                 Serialize::Page.compact(raw, base_url: @config.confluence_web_base_url, include_body: true)
               end
        { "page" => page }
      end

      def list_children(page_id, limit: 50, cursor: nil)
        require_enabled!
        logical = { page_id: page_id.to_s, limit: limit, cursor: cursor }
        @cache.fetch(ns: "children", logical: logical) do
          raw = @confluence.children(page_id, limit: limit, cursor: cursor)
          {
            "page_id" => page_id.to_s,
            "children" => raw[:children],
            "next_cursor" => raw[:next_cursor],
            "total" => raw[:total]
          }
        end
      end

      def space_info(space: nil)
        require_enabled!
        key = space || @config.space
        raise Atlassian::CapabilityError.new("space is not configured", domain: :confluence,
                                                                         hint: "set CLD_SPACE or pass space") if key.to_s.empty?

        { "space" => @confluence.space(key) }
      end

      def page_history(page_id, limit: 50, cursor: nil)
        require_enabled!
        logical = { page_id: page_id.to_s, limit: limit, cursor: cursor }
        fetcher = -> { @confluence.page_history(page_id, limit: limit, cursor: cursor) }
        raw = cursor.nil? ? @cache.fetch(ns: "page_history", logical: logical, &fetcher) : fetcher.call
        {
          "page_id" => page_id.to_s,
          "versions" => raw[:versions],
          "next_cursor" => raw[:next_cursor],
          "total" => raw[:total]
        }
      end

      def page_comments(page_id, limit: 50, cursor: nil)
        require_enabled!
        logical = { page_id: page_id.to_s, limit: limit, cursor: cursor }
        fetcher = -> { @confluence.page_comments(page_id, limit: limit, cursor: cursor) }
        raw = cursor.nil? ? @cache.fetch(ns: "page_comments", logical: logical, &fetcher) : fetcher.call
        {
          "page_id" => page_id.to_s,
          "comments" => raw[:comments],
          "next_cursor" => raw[:next_cursor],
          "total" => raw[:total]
        }
      end

      def labels(page_id)
        require_enabled!
        raw = @cache.fetch(ns: "page_labels", logical: { page_id: page_id.to_s }) do
          @confluence.labels(page_id)
        end
        { "page_id" => page_id.to_s, "labels" => raw[:labels], "total" => raw[:total] }
      end

      def attachments(page_id, limit: 50, cursor: nil)
        require_enabled!
        logical = { page_id: page_id.to_s, limit: limit, cursor: cursor }
        fetcher = -> { @confluence.attachments(page_id, limit: limit, cursor: cursor) }
        raw = cursor.nil? ? @cache.fetch(ns: "page_attachments", logical: logical, &fetcher) : fetcher.call
        {
          "page_id" => page_id.to_s,
          "attachments" => raw[:attachments],
          "next_cursor" => raw[:next_cursor],
          "total" => raw[:total]
        }
      end

      def attachment(page_id, attachment_id: nil, filename: nil)
        require_enabled!
        @confluence.attachment(page_id, attachment_id: attachment_id, filename: filename)
      end

      def space_tree(space: nil, depth: 2, limit: 100)
        require_enabled!
        space_key = space || @config.space
        raise Atlassian::CapabilityError.new("space is not configured", domain: :confluence,
                                                                         hint: "set CLD_SPACE or pass space") if space_key.to_s.empty?

        depth = depth.to_i.clamp(1, 5)
        limit = limit.to_i.clamp(1, 500)
        pages = fetch_space_pages(space_key, limit)
        {
          "space" => space_key,
          "depth" => depth,
          "nodes" => build_tree(pages, depth, limit),
          "total" => pages.length
        }
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

      def fetch_space_pages(space_key, limit)
        pages = []
        cursor = nil
        loop do
          remaining = limit - pages.length
          break if remaining <= 0

          raw = @confluence.space_pages(space_key, limit: [remaining, 50].min, cursor: cursor)
          pages.concat(raw[:pages])
          cursor = raw[:next_cursor]
          break if cursor.nil?
        end
        pages.first(limit)
      end

      def build_tree(pages, max_depth, limit)
        nodes = {}
        pages.each do |page|
          ancestors = Array(page["ancestors"])
          nodes[page["id"].to_s] = {
            "id" => page["id"].to_s,
            "title" => page["title"],
            "url" => Serialize::Page.url(page, base_url: @config.confluence_web_base_url),
            "parent_id" => ancestors.last&.dig("id")&.to_s,
            "depth" => ancestors.length,
            "children" => []
          }
        end

        included = nodes.values.select { |node| node["depth"] < max_depth }.first(limit)
        included_ids = included.to_h { |node| [node["id"], true] }
        roots = []
        included.each do |node|
          parent = nodes[node["parent_id"]]
          if parent && included_ids[parent["id"]]
            parent["children"] << node
          else
            roots << node
          end
        end
        roots
      end

      def fetch_page(id)
        meta = @cache.fetch(ns: "page_meta", logical: { id: id.to_s }) do
          raw = @confluence.page(id, include_body: false)
          { "version" => raw.dig("version", "number") || raw.dig("version", "when"),
            "title" => raw["title"] }
        end
        version = meta["version"]
        logical = { id: id.to_s, version: version }
        @cache.fetch(ns: "page_body", logical: logical) do
          raw = @confluence.page(id)
          Serialize::Page.compact(raw, base_url: @config.confluence_web_base_url, include_body: true)
        end
      end
    end
  end
end
