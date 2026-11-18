# frozen_string_literal: true

module JiraCore
  module Query
    module JQL
      DEFAULT_ORDER = "updated DESC"
      PROJECT_KEY = /\A[A-Z][A-Z0-9_]*\z/
      FORBIDDEN = [
        [/\bproject\b/i, "project"],
        [/\border\s+by\b/i, "ORDER BY"],
        [/;/, ";"],
        [/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "control characters"]
      ].freeze

      module_function

      def wrap(user_query, allowlist:, order_by: DEFAULT_ORDER, max_chars: 2000)
        keys = normalize_allowlist(allowlist)
        raise Atlassian::QueryError.new("project allowlist is empty", query_code: :query_scope_forbidden) if keys.empty?

        user = user_query.to_s.strip
        validate!(user, max_chars: max_chars)
        scope = "project IN (#{keys.join(", ")})"
        body = user.empty? ? scope : "#{scope} AND (#{user})"
        "#{body} ORDER BY #{validate_order!(order_by)}"
      end

      def validate!(query, max_chars: 2000)
        raise Atlassian::QueryError.new("JQL is too long (#{query.length} > #{max_chars})", query_code: :query_too_large) if query.length > max_chars.to_i

        FORBIDDEN.each do |pattern, label|
          if query.match?(pattern)
            raise Atlassian::QueryError.new("JQL contains forbidden #{label}", query_code: :query_scope_forbidden,
                                                                               hint: "JQL is wrapped with the project allowlist server-side")
          end
        end
        raise Atlassian::QueryError.new("JQL has unbalanced quotes", query_code: :query_invalid) unless balanced_quotes?(query)
        raise Atlassian::QueryError.new("JQL has unbalanced parentheses", query_code: :query_invalid) unless balanced_parens?(query)

        true
      end

      def preset(project, id, kind: :jql)
        preset = project&.jql_preset(id)
        raise Atlassian::QueryError.new("unknown JQL preset #{id.inspect}", query_code: :query_preset_unknown) unless preset

        [preset["query"].to_s, preset["order_by"] || DEFAULT_ORDER, (preset["default_limit"] || 20).to_i]
      end

      def text_query(text, field: "text")
        escaped = text.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
        "#{field} ~ \"#{escaped}\""
      end

      def component_query(component)
        "component = \"#{escape_value(component)}\""
      end

      def label_query(label)
        "label = \"#{escape_value(label)}\""
      end

      def combine(*clauses)
        clauses.compact.reject { |c| c.to_s.strip.empty? }.map { |c| "(#{c})" }.join(" AND ")
      end

      def escape_value(value)
        value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
      end

      def normalize_allowlist(allowlist)
        Array(allowlist).map { |key| key.to_s.upcase }.grep(PROJECT_KEY).uniq
      end

      def validate_order!(order_by)
        text = order_by.to_s.strip
        text = DEFAULT_ORDER if text.empty?
        unless text.match?(/\A[a-zA-Z_][a-zA-Z0-9_.]*(?:\s+(?:ASC|DESC))?(?:,\s*[a-zA-Z_][a-zA-Z0-9_.]*(?:\s+(?:ASC|DESC))?)*\z/i)
          raise Atlassian::QueryError.new("invalid JQL order_by #{order_by.inspect}", query_code: :query_invalid)
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
