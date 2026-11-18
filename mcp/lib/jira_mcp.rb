# frozen_string_literal: true

require "zeitwerk"
require "mcp"
require "jira_core"
require_relative "jira_mcp/version"

module JiraMcp
  RUNTIME_KEY = :jira_mcp_runtime

  class << self
    def root
      File.expand_path("..", __dir__)
    end

    def runtime
      Thread.current[RUNTIME_KEY]
    end

    def runtime=(value)
      Thread.current[RUNTIME_KEY] = value
    end

    def with_runtime(value)
      previous = runtime
      self.runtime = value
      yield
    ensure
      self.runtime = previous
    end
  end
end

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "adf" => "ADF",
  "cql" => "CQL",
  "http" => "HTTP",
  "http_app" => "HTTPApp",
  "jql" => "JQL",
  "kb" => "KB",
  "kb_answer" => "KBAnswer",
  "kb_get_page" => "KBGetPage",
  "kb_list_children" => "KBListChildren",
  "kb_page_template" => "KBPageTemplate",
  "kb_search" => "KBSearch"
)
loader.setup
