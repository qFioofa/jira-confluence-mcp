# frozen_string_literal: true

module JiraCld
  module Render
    module ADF
      module_function

      def to_text(document, limit: nil)
        text = render(document).strip
        text = text.gsub(/\n{3,}/, "\n\n")
        limit && text.length > limit ? "#{text[0, limit]}\n[truncated]" : text
      end

      def render(node)
        case node
        when nil
          ""
        when String
          node
        when Array
          node.map { |child| render(child) }.join
        when Hash
          render_node(node)
        else
          node.to_s
        end
      end

      def render_node(node)
        case node["type"]
        when "doc"
          children(node)
        when "paragraph"
          "#{children(node)}\n\n"
        when "heading"
          "#{children(node)}\n\n"
        when "hardBreak"
          "\n"
        when "text"
          text_with_marks(node)
        when "bulletList"
          list(node, "- ")
        when "orderedList"
          ordered_list(node)
        when "listItem"
          "\n#{children(node).strip}\n"
        when "codeBlock"
          "```\n#{children(node).strip}\n```\n\n"
        when "blockquote"
          children(node).strip.lines.map { |line| "> #{line}" }.join + "\n\n"
        when "rule"
          "---\n\n"
        when "mention"
          "@#{dig(node, "attrs", "text") || dig(node, "attrs", "displayName") || dig(node, "attrs", "id")}"
        when "emoji"
          dig(node, "attrs", "text") || ":#{dig(node, "attrs", "shortName")}:"
        when "inlineCard", "blockCard"
          url = dig(node, "attrs", "url")
          url ? "[link](#{url})" : ""
        when "status"
          dig(node, "attrs", "text").to_s
        when "date"
          dig(node, "attrs", "timestamp")
        when "table"
          table(node)
        when "tableRow", "tableCell", "tableHeader"
          children(node)
        when "panel"
          "#{children(node).strip}\n\n"
        when "taskList", "taskItem", "decisionList", "decisionItem"
          children(node)
        else
          children(node)
        end
      end

      def children(node)
        render(node["content"])
      end

      def text_with_marks(node)
        text = node["text"].to_s
        marks = Array(node["marks"])
        marks.each do |mark|
          case mark["type"]
          when "code"
            text = "`#{text}`"
          when "strong"
            text = "**#{text}**"
          when "em"
            text = "*#{text}*"
          when "strike"
            text = "~~#{text}~~"
          when "link"
            href = dig(mark, "attrs", "href")
            text = "[#{text}](#{href})" if href
          end
        end
        text
      end

      def list(node, marker)
        items = Array(node["content"]).map do |item|
          "#{marker}#{render(item).strip}"
        end
        "#{items.join("\n")}\n\n"
      end

      def ordered_list(node)
        items = Array(node["content"]).each_with_index.map do |item, index|
          "#{index + 1}. #{render(item).strip}"
        end
        "#{items.join("\n")}\n\n"
      end

      def table(node)
        rows = Array(node["content"]).map do |row|
          cells = Array(row["content"]).map { |cell| render(cell).strip.gsub(/\s+/, " ") }
          "| #{cells.join(" | ")} |"
        end
        "#{rows.join("\n")}\n\n"
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
