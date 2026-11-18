# frozen_string_literal: true

module JiraCore
  module Serialize
    module Issue
      DEFAULT_FIELDS = %w[
        summary status issuetype priority assignee reporter updated created labels components
        description parent duedate resolution resolutiondate timeestimate timeoriginalestimate
        fixVersions issuelinks attachment
      ].freeze

      module_function

      def compact(issue, base_url: nil, field_map: {}, include_description: true)
        return nil unless issue.is_a?(Hash)

        fields = issue["fields"] || {}
        description = description_text(issue, fields, include_description: include_description)
        {
          "key" => issue["key"],
          "id" => issue["id"],
          "summary" => fields["summary"],
          "status" => dig(fields, "status", "name"),
          "status_category" => dig(fields, "status", "statusCategory", "name"),
          "type" => dig(fields, "issuetype", "name"),
          "priority" => dig(fields, "priority", "name"),
          "assignee" => Person.compact(fields["assignee"]),
          "reporter" => Person.compact(fields["reporter"]),
          "created" => fields["created"],
          "updated" => fields["updated"],
          "due" => fields["duedate"],
          "resolution" => dig(fields, "resolution", "name"),
          "resolution_date" => fields["resolutiondate"],
          "estimate_seconds" => fields["timeestimate"] || fields["timeoriginalestimate"],
          "labels" => Array(fields["labels"]),
          "components" => Array(fields["components"]).filter_map { |c| c["name"] },
          "fix_versions" => Array(fields["fixVersions"]).filter_map { |v| v["name"] },
          "parent" => fields.dig("parent", "key"),
          "description" => description,
          "links" => links(fields["issuelinks"]),
          "attachments" => attachments(fields["attachment"]),
          "url" => base_url ? "#{base_url}/browse/#{issue["key"]}" : nil
        }.compact
      end

      def description_text(issue, fields = nil, include_description: true)
        return nil unless include_description

        fields ||= issue["fields"] || {}
        rendered = issue.dig("renderedFields", "description")
        return Render::HTML.to_text(rendered) if rendered && !rendered.empty?

        raw = fields["description"]
        case raw
        when Hash
          Render::ADF.to_text(raw)
        when String
          raw
        end
      end

      def comments(issue_or_comments, show_email: false)
        comments = if issue_or_comments.is_a?(Hash) && issue_or_comments["comments"].is_a?(Array)
                     issue_or_comments["comments"]
                   else
                     Array(issue_or_comments)
                   end
        comments.map do |comment|
          body = comment["body"]
          text = body.is_a?(Hash) ? Render::ADF.to_text(body) : Render::HTML.to_text(comment["renderedBody"] || body)
          {
            "id" => comment["id"],
            "author" => Person.compact(comment["author"], show_email: show_email),
            "created" => comment["created"],
            "updated" => comment["updated"],
            "body" => text
          }.compact
        end
      end

      def links(items)
        Array(items).filter_map do |link|
          type = dig(link, "type", "name") || dig(link, "type", "outward")
          inward = link["inwardIssue"]
          outward = link["outwardIssue"]
          issue = inward || outward
          next unless issue

          {
            "type" => type,
            "direction" => inward ? "inward" : "outward",
            "key" => issue["key"],
            "summary" => dig(issue, "fields", "summary"),
            "status" => dig(issue, "fields", "status", "name")
          }.compact
        end
      end

      def attachments(items)
        Array(items).map do |item|
          {
            "id" => item["id"],
            "filename" => item["filename"],
            "size" => item["size"],
            "mime_type" => item["mimeType"],
            "created" => item["created"],
            "url" => item["content"],
            "author" => Person.compact(item["author"])
          }.compact
        end
      end

      def changelog(histories)
        Array(histories).flat_map do |history|
          Array(history["items"]).map do |item|
            {
              "id" => history["id"],
              "author" => Person.compact(history["author"]),
              "created" => history["created"],
              "field" => item["field"],
              "from" => item["fromString"],
              "to" => item["toString"]
            }.compact
          end
        end
      end

      def dig(hash, *keys)
        keys.reduce(hash) do |memo, key|
          return nil unless memo.is_a?(Hash)

          memo[key]
        end
      end
    end
  end
end
