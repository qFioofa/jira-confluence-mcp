# frozen_string_literal: true

require_relative "lib/jira_core/version"

Gem::Specification.new do |spec|
  spec.name = "jira_core"
  spec.version = JiraCore::VERSION
  spec.authors = ["ruby-jira-mcp contributors"]
  spec.summary = "Domain layer for Jira and Confluence access"
  spec.description = "HTTP clients, Atlassian adapters, repositories and cache contracts."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", "~> 8.1"
  spec.add_dependency "i18n", "~> 1.15"
  spec.add_dependency "zeitwerk", "~> 2.8"
end
