# frozen_string_literal: true

module JiraCore
  module Serialize
    module Page
      module_function

      def compact(page, base_url: nil, include_body: true)
        return nil unless page.is_a?(Hash)

        version = page.dig("version", "number") || page.dig("version", "when")
        body_html = page.dig("body", "view", "value") || page.dig("body", "storage", "value")
        body_format = page.dig("body", "view", "representation") ||
                      page.dig("body", "storage", "representation") ||
                      (body_html ? "view" : nil)
        {
          "id" => page["id"]&.to_s,
          "title" => page["title"],
          "space" => page.dig("space", "key") || page["spaceId"],
          "version" => version,
          "updated" => page.dig("version", "when") || page["lastModified"],
          "author" => Person.compact(page.dig("version", "by")),
          "url" => url(page, base_url: base_url),
          "body_format" => body_format,
          "body" => include_body ? Render::HTML.to_text(body_html) : nil,
          "excerpt" => excerpt(page)
        }.compact
      end

      def url(page, base_url: nil)
        links = page["_links"] || {}
        base = links["base"] || base_url
        webui = links["webui"]
        return "#{base}#{webui}" if base && webui
        return links["self"] if links["self"]
        return nil unless base && page["id"]

        "#{base}/pages/#{page["id"]}"
      end

      def excerpt(page)
        value = page["excerpt"]
        return nil if value.nil?

        value.is_a?(Hash) ? Render::HTML.to_text(value["value"] || value["text"]) : value.to_s
      end

      def history(results)
        Array(results).map do |version|
          {
            "number" => version["number"],
            "when" => version["when"],
            "author" => Person.compact(version["by"]),
            "message" => version["message"],
            "minor_edit" => version["minorEdit"]
          }.compact
        end
      end

      def comments(results)
        Array(results).map do |comment|
          body = comment.dig("body", "view", "value") || comment.dig("body", "storage", "value")
          {
            "id" => comment["id"]&.to_s,
            "title" => comment["title"],
            "author" => Person.compact(comment.dig("version", "by") || comment["author"]),
            "created" => comment.dig("version", "when") || comment["created"],
            "body" => Render::HTML.to_text(body),
            "location" => comment.dig("extensions", "location")
          }.compact
        end
      end

      def labels(results)
        Array(results).map do |label|
          {
            "id" => label["id"]&.to_s,
            "name" => label["name"],
            "prefix" => label["prefix"]
          }.compact
        end
      end

      def attachments(results, base_url: nil)
        Array(results).map do |item|
          links = item["_links"] || {}
          download = links["download"]
          base = links["base"] || base_url
          download = "#{base}#{download}" if download && base && !download.match?(%r{\Ahttps?://})
          {
            "id" => item["id"]&.to_s,
            "filename" => item["title"] || item["filename"],
            "media_type" => item.dig("extensions", "mediaType") || item["mediaType"],
            "size" => item.dig("extensions", "fileSize") || item["fileSize"],
            "download_url" => download,
            "author" => Person.compact(item.dig("version", "by")),
            "updated" => item.dig("version", "when")
          }.compact
        end
      end

      def children(page)
        results = page["results"] || page["_embedded"]&.values&.first || []
        Array(results).map do |child|
          {
            "id" => child["id"]&.to_s,
            "title" => child["title"],
            "version" => child.dig("version", "number"),
            "url" => url(child),
            "child_count" => child["childCount"]
          }.compact
        end
      end
    end
  end
end
