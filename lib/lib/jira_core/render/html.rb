# frozen_string_literal: true

module JiraCore
  module Render
    module HTML
      module_function

      def to_text(html, limit: nil)
        return "" if html.nil? || html.to_s.empty?

        text = if nokogiri?
                 strip_with_nokogiri(html.to_s)
               else
                 fallback_strip(html.to_s)
               end
        text = text.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
        limit && text.length > limit ? "#{text[0, limit]}\n[truncated]" : text
      end

      def nokogiri?
        if @nokogiri.nil?
          @nokogiri = begin
            require "nokogiri"
            true
          rescue LoadError
            false
          end
        end
        @nokogiri
      end

      def strip_with_nokogiri(html)
        document = Nokogiri::HTML5.fragment(html)
        document.css("script, style, noscript").remove
        document.css("br").each { |node| node.replace("\n") }
        document.css("p, div, li, tr, h1, h2, h3, h4, h5, h6, pre, blockquote").each do |node|
          node.add_next_sibling("\n")
        end
        document.css("li").each { |node| node.prepend("- ") }
        document.text
      rescue StandardError
        fallback_strip(html)
      end

      def fallback_strip(html)
        text = html.gsub(%r{<(script|style|noscript)[^>]*>.*?</\1>}im, " ")
        text = text.gsub(%r{<br\s*/?>}i, "\n")
        text = text.gsub(%r{</(p|div|li|tr|h[1-6]|pre|blockquote)>}i, "\n")
        text = text.gsub(/<li[^>]*>/i, "- ")
        text = text.gsub(/<[^>]+>/, " ")
        text.gsub("&nbsp;", " ").gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">")
            .gsub("&quot;", '"').gsub("&#39;", "'")
      end
    end
  end
end
