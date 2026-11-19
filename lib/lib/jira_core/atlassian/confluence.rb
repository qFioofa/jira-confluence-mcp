# frozen_string_literal: true

require "uri"

module JiraCore
  module Atlassian
    class Confluence
      V1 = "/rest/api"
      V2 = "/api/v2"

      attr_reader :client, :config, :reference

      def initialize(client:, config:, reference: nil, logger: nil)
        @client = client
        @config = config
        @reference = reference
        @logger = logger
      end

      def space(key)
        cache_key = "space:#{key}"
        if reference
          cached = reference.get(:reference, cache_key)
          return cached if cached
        end
        response = client.get("#{V1}/space/#{escape_path(key)}", headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        data = response.json
        result = {
          id: data["id"]&.to_s,
          key: data["key"],
          name: data["name"],
          type: data["type"],
          url: page_url(data, base_url: config.confluence_web_base_url)
        }.compact
        reference&.put(:reference, cache_key, result)
        result
      end

      def page(id, include_body: true)
        v1_query = { expand: include_body ? "body.view,version,space" : "version,space" }
        if config.cloud?
          query = include_body ? { "body-format" => "view" } : {}
          response = client.get("#{V2}/pages/#{escape_path(id)}", query: query, headers: auth_headers)
          if [404, 410].include?(response.status)
            @logger&.warn("confluence v2 page endpoint unavailable, falling back to v1", page_id: id)
            response = client.get("#{V1}/content/#{escape_path(id)}", query: v1_query, headers: auth_headers)
          end
        else
          response = client.get("#{V1}/content/#{escape_path(id)}", query: v1_query, headers: auth_headers)
        end
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        enforce_space!(response.json)
      end

      def page_by_title(title, space)
        params = { title: title, spaceKey: space, expand: "body.view,version,space", limit: 1 }
        response = client.get("#{V1}/content", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        data = response.json
        page = Array(data["results"]).first
        raise NotFoundError.new("page #{title.inspect} not found in space #{space}", domain: :confluence, status: 404) unless page

        enforce_space!(page)
      end

      def children(page_id, limit: 50, cursor: nil)
        limit = limit.to_i.clamp(1, 50)
        data = Cursor.decode(cursor) || {}
        if config.cloud?
          params = { limit: limit }
          params[:cursor] = data[:c] if data[:c]
          response = client.get("#{V2}/pages/#{escape_path(page_id)}/children", query: params, headers: auth_headers)
          if [404, 410].include?(response.status)
            response = client.get(
              "#{V1}/content/#{escape_path(page_id)}/child/page",
              query: { limit: limit, start: data[:s] || 0 }, headers: auth_headers
            )
          end
          Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
          payload = response.json
          Array(payload["results"])
          next_cursor = nil
          if payload["_links"] && payload["_links"]["next"]
            raw = URI.decode_www_form(URI.parse(payload["_links"]["next"]).query.to_s).to_h["cursor"]
            next_cursor = raw && Cursor.encode(k: "kb_children", c: raw)
          end
          return { children: Serialize::Page.children(payload), next_cursor: next_cursor, total: payload["results"]&.length }
        end

        params = { limit: limit, start: data[:s] || 0, expand: "version,space" }
        response = client.get("#{V1}/content/#{escape_path(page_id)}/child/page", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        payload = response.json
        results = Array(payload["results"])
        start = payload["start"].to_i
        total = payload["total"]
        next_start = start + results.length
        more = total ? next_start < total.to_i : results.length >= limit
        {
          children: Serialize::Page.children(payload),
          next_cursor: more ? Cursor.encode(k: "kb_children", s: next_start) : nil,
          total: total
        }
      end

      def page_history(id, limit: 50, cursor: nil)
        ensure_page_scope!(id)
        limit = limit.to_i.clamp(1, 50)
        data = Cursor.decode(cursor) || {}
        params = { limit: limit, start: data[:s] || 0 }
        response = client.get("#{V1}/content/#{escape_path(id)}/version", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        payload = response.json
        results = Array(payload["results"])
        start = payload["start"].to_i
        total = payload["total"]
        next_start = start + results.length
        more = total ? next_start < total.to_i : results.length >= limit
        {
          page_id: id.to_s,
          versions: Serialize::Page.history(results),
          next_cursor: more ? Cursor.encode(k: "kb_history", s: next_start) : nil,
          total: total
        }
      end

      def page_comments(id, limit: 50, cursor: nil)
        ensure_page_scope!(id)
        limit = limit.to_i.clamp(1, 50)
        data = Cursor.decode(cursor) || {}
        params = { limit: limit, start: data[:s] || 0, expand: "body.view,version" }
        response = client.get("#{V1}/content/#{escape_path(id)}/child/comment", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        payload = response.json
        results = Array(payload["results"])
        start = payload["start"].to_i
        total = payload["total"]
        next_start = start + results.length
        more = total ? next_start < total.to_i : results.length >= limit
        {
          page_id: id.to_s,
          comments: Serialize::Page.comments(results),
          next_cursor: more ? Cursor.encode(k: "kb_comments", s: next_start) : nil,
          total: total
        }
      end

      def labels(id)
        ensure_page_scope!(id)
        response = client.get("#{V1}/content/#{escape_path(id)}/label", headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        results = Array(response.json["results"])
        { page_id: id.to_s, labels: Serialize::Page.labels(results), total: results.length }
      end

      def attachments(id, limit: 50, cursor: nil)
        ensure_page_scope!(id)
        limit = limit.to_i.clamp(1, 50)
        data = Cursor.decode(cursor) || {}
        params = { limit: limit, start: data[:s] || 0, expand: "version" }
        response = client.get("#{V1}/content/#{escape_path(id)}/child/attachment", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        payload = response.json
        results = Array(payload["results"])
        start = payload["start"].to_i
        total = payload["total"]
        next_start = start + results.length
        more = total ? next_start < total.to_i : results.length >= limit
        {
          page_id: id.to_s,
          attachments: Serialize::Page.attachments(results, base_url: config.confluence_web_base_url),
          next_cursor: more ? Cursor.encode(k: "kb_attachments", s: next_start) : nil,
          total: total
        }
      end

      def attachment(id, attachment_id: nil, filename: nil)
        ensure_page_scope!(id)
        response = client.get("#{V1}/content/#{escape_path(id)}/child/attachment",
                              query: { limit: 100, expand: "version" }, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        results = Array(response.json["results"])
        item = if !attachment_id.to_s.empty?
                 results.find { |entry| entry["id"].to_s == attachment_id.to_s }
               elsif !filename.to_s.empty?
                 results.find { |entry| (entry["title"] || entry["filename"]).to_s == filename.to_s }
               else
                 results.first
               end
        raise NotFoundError.new("attachment not found on page #{id}", domain: :confluence, status: 404) unless item

        path = "#{V1}/content/#{escape_path(id)}/child/attachment/#{escape_path(item["id"])}/download"
        binary = client.get(path, headers: auth_headers.merge("Accept" => "*/*"))
        Errors.raise_for!(binary, domain: :confluence, deployment: config.deployment)
        bytes = binary.body.to_s
        {
          id: item["id"],
          filename: item["title"] || item["filename"],
          mime_type: item.dig("extensions", "mediaType") || item["mediaType"],
          size: item.dig("extensions", "fileSize") || item["fileSize"],
          bytes: bytes,
          content_type: binary.headers["content-type"],
          inline: bytes.bytesize <= MAX_INLINE_BYTES
        }
      end

      def space_pages(space_key, limit: 100, cursor: nil)
        limit = limit.to_i.clamp(1, 100)
        data = Cursor.decode(cursor) || {}
        params = {
          spaceKey: space_key,
          type: "page",
          expand: "ancestors,version,space",
          limit: limit,
          start: data[:s] || 0
        }
        response = client.get("#{V1}/content", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        payload = response.json
        results = Array(payload["results"]).map { |page| enforce_space!(page) }
        start = payload["start"].to_i
        total = payload["total"]
        next_start = start + results.length
        more = total ? next_start < total.to_i : results.length >= limit
        {
          pages: results,
          next_cursor: more ? Cursor.encode(k: "kb_space_pages", s: next_start) : nil,
          total: total
        }
      end

      def search(cql:, limit: 10, cursor: nil)
        limit = limit.to_i.clamp(1, 50)
        data = Cursor.decode(cursor) || {}
        params = {
          cql: cql,
          limit: limit,
          start: data[:s] || 0,
          expand: "version,space"
        }
        response = client.get("#{V1}/content/search", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :confluence, deployment: config.deployment)
        payload = response.json
        results = Array(payload["results"]).map { |page| enforce_space!(page) }
        start = payload["start"].to_i
        total = payload["total"]
        next_start = start + results.length
        more = total ? next_start < total.to_i : results.length >= limit
        {
          pages: results,
          next_cursor: more ? Cursor.encode(k: "kb_search", s: next_start) : nil,
          total: total
        }
      end

      def capabilities
        {
          deployment: config.deployment,
          space_resolve: true,
          pages: true,
          children: config.cloud? ? "v2:cursor" : "v1:start",
          history: true,
          comments: true,
          labels: true,
          attachments: "metadata+download",
          search: "v1:cql",
          body_format: "view"
        }
      end

      private

      MAX_INLINE_BYTES = 5 * 1024 * 1024

      def auth_headers
        Auth.headers(config, service: :confluence)
      end

      def ensure_page_scope!(id)
        page(id, include_body: false)
      end

      def enforce_space!(page)
        allowed = config.spaces
        return page if allowed.empty?

        space_key = page.dig("space", "key") || page["spaceKey"]
        if space_key.nil?
          webui = page.dig("_links", "webui").to_s
          space_key = webui[%r{/spaces/([^/]+)/}, 1]
        end
        return page if space_key && allowed.include?(space_key)

        if page["spaceId"]
          mapped = reference&.get(:reference, :confluence_space_ids) || {}
          return page if mapped[page["spaceId"].to_s] && allowed.include?(mapped[page["spaceId"].to_s])
        end

        raise Error.new("page #{page["id"]} is outside the space allowlist", code: :scope_forbidden,
                                                                             domain: :confluence, hint: "post-filter rejected cross-space data")
      end

      def page_url(data, base_url: nil)
        links = data["_links"] || {}
        base = links["base"] || base_url
        webui = links["webui"]
        return "#{base}#{webui}" if base && webui

        nil
      end

      def escape_path(value)
        require "uri"
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
