# frozen_string_literal: true

require "json"

module JiraCld
  module Prompts
    module Helpers
      module_function

      def text_result(text, description: nil)
        MCP::Prompt::Result.new(
          description: description,
          messages: [
            MCP::Prompt::Message.new(role: "user", content: MCP::Content::Text.new(text))
          ]
        )
      end

      def json(value)
        JSON.pretty_generate(Tools::Support.normalize(value))
      end

      def runtime
        JiraCld.runtime
      end

      def error_text(error)
        code = error.respond_to?(:code) ? error.code.to_s : "error"
        "#{code}: #{error.message}"
      end
    end
  end
end
