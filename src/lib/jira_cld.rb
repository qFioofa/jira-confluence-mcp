# frozen_string_literal: true

require "zeitwerk"
require "mcp"
require_relative "jira_cld/version"

module JiraCld
  class << self
    attr_accessor :runtime

    def root
      File.expand_path("..", __dir__)
    end

    def env
      ENV
    end
  end
end

loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path("jira_cld", __dir__), namespace: JiraCld)
loader.inflector.inflect(
  "adf" => "ADF",
  "cli" => "CLI",
  "cql" => "CQL",
  "db" => "DB",
  "html" => "HTML",
  "http" => "HTTP",
  "i18n" => "I18n",
  "jql" => "JQL",
  "kb" => "KB",
  "kb_search" => "KBSearch",
  "kb_get_page" => "KBGetPage",
  "kb_list_children" => "KBListChildren",
  "kb_answer" => "KBAnswer",
  "kb_page_template" => "KBPageTemplate",
  "ui" => "UI"
)
loader.setup
