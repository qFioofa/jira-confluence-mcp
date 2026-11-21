# frozen_string_literal: true

require "zeitwerk"
require_relative "jira_core/version"

module JiraCore
  class << self
    def root
      File.expand_path("..", __dir__)
    end
  end
end

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "adf" => "ADF",
  "cql" => "CQL",
  "html" => "HTML",
  "http" => "HTTP",
  "jql" => "JQL"
)
loader.setup
