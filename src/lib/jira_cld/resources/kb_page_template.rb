# frozen_string_literal: true

require "json"

module JiraCld
  module Resources
    class KBPageTemplate < MCP::ResourceTemplate
      uri_template "kb://page/{id}"
      resource_template_name "kb_page"
      title JiraCld::I18n.t("resources.kb_page.title")
      description JiraCld::I18n.t("resources.kb_page.description")
      mime_type "application/json"

      def self.contents(id:, server_context: nil)
        data = JiraCld.runtime.knowledge_base.get_page(id: id)
        MCP::Resource::TextContents.new(
          uri: "kb://page/#{id}",
          mime_type: "application/json",
          text: JSON.pretty_generate(Tools::Support.normalize(data))
        )
      rescue StandardError => e
        MCP::Resource::TextContents.new(
          uri: "kb://page/#{id}",
          mime_type: "application/json",
          text: JSON.pretty_generate("error" => { "code" => "resource_error", "message" => e.message })
        )
      end
    end
  end
end
