# frozen_string_literal: true

module JiraCore
  module Query
    module CQL
      DEFAULT_ORDER = "lastmodified DESC"
      FORBIDDEN = [
        [/\bspace\b/i, "space"],
        [/\border\s+by\b/i, "ORDER BY"],
        [/;/, ";"],
        [/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "control characters"]
      ].freeze

      module_function

      def wrap(user_cql, allowlist:, order_by: DEFAULT_ORDER, max_chars: 2000)
        spaces = normalize_allowlist(allowlist)
        raise Atlassian::QueryError.new("space allowlist is empty", query_code: :query_scope_forbidden) if spaces.empty?

        user = user_cql.to_s.strip
        validate!(user, max_chars: max_chars)
        scope = "space IN (#{spaces.map { |space| "\"#{escape(space)}\"" }.join(", ")})"
        body = user.empty? ? scope : "#{scope} AND (#{user})"
        "#{body} ORDER BY #{validate_order!(order_by)}"
      end

      def validate!(query, max_chars: 2000)
        raise Atlassian::QueryError.new("CQL is too long (#{query.length} > #{max_chars})", query_code: :query_too_large) if query.length > max_chars.to_i

        FORBIDDEN.each do |pattern, label|
          if query.match?(pattern)
            raise Atlassian::QueryError.new("CQL contains forbidden #{label}", query_code: :query_scope_forbidden,
                                                                               hint: "CQL is wrapped with the space allowlist server-side")
          end
        end
        raise Atlassian::QueryError.new("CQL has unbalanced quotes", query_code: :query_invalid) unless balanced_quotes?(query)
        raise Atlassian::QueryError.new("CQL has unbalanced parentheses", query_code: :query_invalid) unless balanced_parens?(query)

        true
      end

      def preset(project, id)
        preset = project&.cql_preset(id)
        raise Atlassian::QueryError.new("unknown CQL preset #{id.inspect}", query_code: :query_preset_unknown) unless preset

        [preset["query"].to_s, preset["order_by"] || DEFAULT_ORDER, (preset["default_limit"] || 10).to_i]
      end

      def text_query(text)
        "text ~ \"#{escape(text)}\""
      end

      def label_query(label)
        "label = \"#{escape(label)}\""
      end

      def combine(*clauses)
        clauses.compact.reject { |c| c.to_s.strip.empty? }.map { |c| "(#{c})" }.join(" AND ")
      end

      def escape(value)
        value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
      end

      def normalize_allowlist(allowlist)
        Array(allowlist).map(&:to_s).reject(&:empty?).uniq
      end

      def validate_order!(order_by)
        text = order_by.to_s.strip
        text = DEFAULT_ORDER if text.empty?
        unless text.match?(/\A[a-zA-Z_][a-zA-Z0-9_.]*(?:\s+(?:ASC|DESC))?(?:,\s*[a-zA-Z_][a-zA-Z0-9_.]*(?:\s+(?:ASC|DESC))?)*\z/i)
          raise Atlassian::QueryError.new("invalid CQL order_by #{order_by.inspect}", query_code: :query_invalid)
        end

        text
      end

      def balanced_quotes?(text)
        in_quote = false
        escaped = false
        text.each_char do |char|
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            in_quote = !in_quote
          end
        end
        !in_quote
      end

      def balanced_parens?(text)
        depth = 0
        in_quote = false
        escaped = false
        text.each_char do |char|
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            in_quote = !in_quote
          elsif !in_quote
            depth += 1 if char == "("
            depth -= 1 if char == ")"
            return false if depth.negative?
          end
        end
        depth.zero?
      end
    end
  end
end
